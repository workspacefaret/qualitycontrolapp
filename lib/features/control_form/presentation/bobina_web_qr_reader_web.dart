import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Lector de QR para la tarja de bobina en Flutter Web, usando jsQR en vez
/// del backend ZXing.js que trae `mobile_scanner` en Web.
///
/// Motivo: se confirmó (instrumentación temporal + revisión de
/// zxing-js 0.19.1) que `mobile_scanner` en Web decodifica el frame nativo
/// completo de la cámara sin ningún recorte relacionado al widget/overlay
/// visual, así que el bug portrait-vs-landscape no era de encuadre en
/// Flutter. La causa quedó acotada al motor de decodificación (ZXing.js)
/// fallando con este QR denso en la orientación/resolución que negocia el
/// navegador en portrait. `consumo_papel` (mismo tipo de QR de tarja) usa
/// jsQR con el mismo patrón de captura (canvas a resolución nativa del
/// video) y sí funciona en ambas orientaciones, así que se replica aquí
/// exclusivamente para este escáner.
///
/// Además, igual que `consumo_papel/public/qr_scan.js`, complementa jsQR con
/// `@zxing/browser` para códigos de barra 1D (code128/39/codabar/itf/
/// ean13/ean8/upcA/upcE): jsQR solo decodifica QR, así que sin esto un
/// código de barra 1D nunca se detecta en el escáner Web de bobina (el
/// escáner nativo Android/iOS en `bobina_qr_scanner_page.dart` ya soporta
/// esos formatos vía `mobile_scanner`, este es el único hueco).
@JS('jsQR')
external _JsQrResult? _jsQr(JSUint8ClampedArray data, int width, int height);

extension type _JsQrResult._(JSObject _) implements JSObject {
  external String get data;
}

class BobinaWebQrReaderView extends StatefulWidget {
  const BobinaWebQrReaderView({super.key, required this.onDetect});

  final ValueChanged<String> onDetect;

  @override
  State<BobinaWebQrReaderView> createState() => _BobinaWebQrReaderViewState();
}

class _BobinaWebQrReaderViewState extends State<BobinaWebQrReaderView> {
  static const _jsQrScriptUrl = 'https://unpkg.com/jsqr@1.4.0/dist/jsQR.js';
  static bool _jsQrScriptRequested = false;
  static const _zxingScriptUrl = 'https://unpkg.com/@zxing/browser@0.2.1';
  static bool _zxingScriptRequested = false;
  static const _zxingBarcodeFormatNames = [
    'CODE_128',
    'CODE_39',
    'CODABAR',
    'ITF',
    'EAN_13',
    'EAN_8',
    'UPC_A',
    'UPC_E',
  ];
  static int _instanceCounter = 0;

  late final String _viewType;
  late final web.HTMLVideoElement _video;
  late final web.HTMLCanvasElement _canvas;

  web.MediaStream? _stream;
  bool _detected = false;
  bool _running = false;
  String? _errorMessage;
  int _barcodeFrameCounter = 0;
  JSObject? _zxingReader;

  @override
  void initState() {
    super.initState();

    _instanceCounter += 1;
    _viewType = 'bobina-web-qr-reader-$_instanceCounter';

    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    _canvas = web.HTMLCanvasElement();

    final container = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..append(_video);

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => container,
    );

    // Se pide de inmediato y sin esperar: es un respaldo (código de barra
    // 1D), no debe retrasar el arranque de la cámara ni el QR, que sigue
    // siendo el camino principal.
    _ensureZxingScriptRequested();

    unawaited(_start());
  }

  bool get _jsQrAvailable => web.window.has('jsQR');

  Future<void> _ensureJsQrLoaded() async {
    if (_jsQrAvailable) return;

    if (!_jsQrScriptRequested) {
      _jsQrScriptRequested = true;
      final script = web.HTMLScriptElement()..src = _jsQrScriptUrl;
      web.document.head!.append(script);
    }

    var attempts = 0;
    while (!_jsQrAvailable) {
      attempts++;
      if (attempts > 150) {
        throw Exception('No se pudo cargar la librería jsQR (unpkg.com)');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _ensureZxingScriptRequested() {
    if (_zxingScriptRequested) return;
    _zxingScriptRequested = true;
    final script = web.HTMLScriptElement()..src = _zxingScriptUrl;
    web.document.head!.append(script);
  }

  /// Crea (una sola vez) el `BrowserMultiFormatReader` de `@zxing/browser`
  /// restringido a los mismos 8 formatos 1D que ya usa `consumo_papel` y el
  /// escáner nativo de bobina (`bobina_qr_scanner_page.dart`). Devuelve
  /// `null` mientras el script todavía no termina de cargar desde el CDN.
  JSObject? _getOrCreateZxingReader() {
    final cached = _zxingReader;
    if (cached != null) return cached;

    if (!web.window.has('ZXingBrowser')) return null;
    final ns = web.window.getProperty<JSObject>('ZXingBrowser'.toJS);

    if (!ns.has('BrowserMultiFormatReader')) return null;
    final readerCtor = ns.getProperty<JSFunction>(
      'BrowserMultiFormatReader'.toJS,
    );

    final reader = readerCtor.callAsConstructor<JSObject>();

    if (ns.has('BarcodeFormat')) {
      final barcodeFormatNs = ns.getProperty<JSObject>('BarcodeFormat'.toJS);
      final formats = _zxingBarcodeFormatNames
          .map((name) => barcodeFormatNs.getProperty<JSAny?>(name.toJS))
          .whereType<JSAny>()
          .toList()
          .toJS;
      reader.setProperty('possibleFormats'.toJS, formats);
    }

    _zxingReader = reader;
    return reader;
  }

  /// Igual que `decodeBarcode()` en `consumo_papel/public/qr_scan.js`: si el
  /// frame no trae un código de barra legible, `decodeFromCanvas` lanza una
  /// excepción JS (comportamiento normal de ZXing) — no significa error.
  String? _decodeBarcode(JSObject reader, web.HTMLCanvasElement canvas) {
    try {
      final result = reader.callMethod<JSObject?>(
        'decodeFromCanvas'.toJS,
        canvas,
      );
      if (result == null) return null;
      final text = result.callMethod<JSString?>('getText'.toJS);
      return text?.toDart;
    } catch (_) {
      return null;
    }
  }

  Future<void> _start() async {
    try {
      await _ensureJsQrLoaded();

      final constraints = web.MediaStreamConstraints(
        video: web.MediaTrackConstraints(facingMode: 'environment'.toJS),
        audio: false.toJS,
      );

      final stream =
          await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

      if (!mounted) {
        for (final track in stream.getTracks().toDart) {
          track.stop();
        }
        return;
      }

      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;

      _running = true;
      _scheduleTick();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo acceder a la cámara: $error';
      });
    }
  }

  void _scheduleTick() {
    web.window.requestAnimationFrame(((JSAny _) => _tick()).toJS);
  }

  void _tick() {
    if (!_running || _detected) return;

    final w = _video.videoWidth;
    final h = _video.videoHeight;

    if (w > 0 && h > 0) {
      _canvas.width = w;
      _canvas.height = h;

      final ctx = _canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(_video, 0, 0, w.toDouble(), h.toDouble());

      final imageData = ctx.getImageData(0, 0, w, h);
      final result = _jsQr(imageData.data, w, h);

      if (result != null && result.data.trim().isNotEmpty) {
        _detected = true;
        _stopCamera();
        widget.onDetect(result.data.trim());
        return;
      }

      // Código de barras 1D (complementa al QR, igual que en
      // consumo_papel/public/qr_scan.js): se intenta cada 3 frames porque
      // decodeFromCanvas es más costoso que jsQR, y solo cuando el frame no
      // trajo un QR.
      _barcodeFrameCounter++;
      if (_barcodeFrameCounter % 3 == 0) {
        final reader = _getOrCreateZxingReader();
        if (reader != null) {
          final barcodeText = _decodeBarcode(reader, _canvas);
          if (barcodeText != null && barcodeText.trim().isNotEmpty) {
            _detected = true;
            _stopCamera();
            widget.onDetect(barcodeText.trim());
            return;
          }
        }
      }
    }

    _scheduleTick();
  }

  void _stopCamera() {
    _running = false;
    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
      _stream = null;
    }
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return HtmlElementView(viewType: _viewType);
  }
}
