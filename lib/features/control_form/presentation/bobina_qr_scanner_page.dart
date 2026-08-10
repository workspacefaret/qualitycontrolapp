import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'bobina_web_qr_reader_stub.dart'
    if (dart.library.js_interop) 'bobina_web_qr_reader_web.dart';

class BobinaQrScannerPage extends StatefulWidget {
  const BobinaQrScannerPage({Key? key}) : super(key: key);

  @override
  State<BobinaQrScannerPage> createState() => _BobinaQrScannerPageState();
}

class _BobinaQrScannerPageState extends State<BobinaQrScannerPage> {
  bool _codeDetected = false;

  // En Web, mobile_scanner usa ZXing.js internamente: se confirmó (con
  // instrumentación temporal + revisión del código fuente de mobile_scanner
  // 5.2.3 y de zxing-js) que ese motor decodifica el frame nativo completo
  // de la cámara según la resolución que negocia el navegador vía
  // getUserMedia, y que en algunos teléfonos falla en portrait con este QR
  // denso de tarja aunque el recuadro visual esté bien encuadrado. En
  // Android/iOS nativo, mobile_scanner usa el motor nativo de la plataforma
  // (no ZXing.js) y no está reportado como afectado, así que ahí se
  // mantiene sin cambios.
  //
  // Restringido a los formatos reales de tarja (QR + los mismos formatos de
  // código de barra 1D que soporta el sistema original consumo_papel vía
  // ZXing) en vez de todos los formatos que mobile_scanner intenta por
  // defecto.
  final MobileScannerController? _controller = kIsWeb
      ? null
      : MobileScannerController(
          formats: const [
            BarcodeFormat.qrCode,
            BarcodeFormat.code128,
            BarcodeFormat.code39,
            BarcodeFormat.codabar,
            BarcodeFormat.itf,
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.upcA,
            BarcodeFormat.upcE,
          ],
          detectionSpeed: DetectionSpeed.unrestricted,
          cameraResolution: const Size(1280, 720),
        );

  void _handleCode(String code) {
    if (_codeDetected) return;
    if (code.trim().isEmpty) return;

    _codeDetected = true;

    Navigator.of(context).pop(code.trim());
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null) return;

    _handleCode(code);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Escanear tarja de bobina'),
      ),
      body: Stack(
        children: [
          if (kIsWeb)
            BobinaWebQrReaderView(onDetect: _handleCode)
          else
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
            ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF22C55E),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Apunta la cámara a la tarja de la bobina',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
