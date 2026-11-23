import 'package:flutter/foundation.dart';

/// Clasificación de un pallet. Significado interno (no se muestra al operador):
/// AZUL = en revisión, ROJO = malo / listo para destrucción, VERDE = bueno.
enum ColorPallet {
  azul('AZUL'),
  rojo('ROJO'),
  verde('VERDE');

  final String valor;
  const ColorPallet(this.valor);

  static ColorPallet? desdeValor(String? v) {
    for (final c in ColorPallet.values) {
      if (c.valor == v) return c;
    }
    return null;
  }
}

/// Máximo de pallets por inspección (mismo tope que el backend).
const int maxPalletsPorInspeccion = 30;

final RegExp _reCodigoPallet = RegExp(r'^\d{1,12}-\d{1,4}$');
final RegExp _reCodigoRegistro = RegExp(r'^\d{1,12}$');

/// Código de tarja válido: "<registro>-<n° de etiqueta>" o solo el número de registro.
bool esCodigoTarjaValido(String texto) {
  final t = texto.trim();
  return _reCodigoPallet.hasMatch(t) || _reCodigoRegistro.hasMatch(t);
}

bool esCodigoPallet(String texto) => _reCodigoPallet.hasMatch(texto.trim());

/// Clasificación vigente de un pallet (se informa al reescanearlo).
class EstadoPallet {
  final ColorPallet? color;
  final String? clasificadoEn;

  const EstadoPallet({this.color, this.clasificadoEn});

  factory EstadoPallet.fromJson(Map<String, dynamic> json) => EstadoPallet(
        color: ColorPallet.desdeValor(json['color']?.toString()),
        clasificadoEn: json['clasificadoEn']?.toString(),
      );
}

/// Datos de la tarja recuperados de FPS (o solo el código si no hubo conexión).
class TarjaPallet {
  final String codigo;
  final int? totalEtiquetas;
  final num? cantidad;
  final String? fechaTarja;
  final String? ordenFabricacion;
  final String? npFaret;
  final String? npInnpack;
  final String? cliente;
  final String? itemNp;
  final String? codigoProducto;
  final String? producto;
  final String? proceso;
  final String? maquina;
  final String? operador;
  final EstadoPallet? estadoActual;

  /// false cuando solo se conoce el código (sin conexión con producción).
  final bool conDatos;

  const TarjaPallet({
    required this.codigo,
    this.totalEtiquetas,
    this.cantidad,
    this.fechaTarja,
    this.ordenFabricacion,
    this.npFaret,
    this.npInnpack,
    this.cliente,
    this.itemNp,
    this.codigoProducto,
    this.producto,
    this.proceso,
    this.maquina,
    this.operador,
    this.estadoActual,
    this.conDatos = true,
  });

  const TarjaPallet.soloCodigo(this.codigo)
      : totalEtiquetas = null,
        cantidad = null,
        fechaTarja = null,
        ordenFabricacion = null,
        npFaret = null,
        npInnpack = null,
        cliente = null,
        itemNp = null,
        codigoProducto = null,
        producto = null,
        proceso = null,
        maquina = null,
        operador = null,
        estadoActual = null,
        conDatos = false;

  static String? _s(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  factory TarjaPallet.fromJson(Map<String, dynamic> json) => TarjaPallet(
        codigo: json['codigo'].toString(),
        totalEtiquetas: json['totalEtiquetas'] is num
            ? (json['totalEtiquetas'] as num).toInt()
            : null,
        cantidad: json['cantidad'] is num ? json['cantidad'] as num : null,
        fechaTarja: _s(json['fechaTarja']),
        ordenFabricacion: _s(json['ordenFabricacion']),
        npFaret: _s(json['npFaret']),
        npInnpack: _s(json['npInnpack']),
        cliente: _s(json['cliente']),
        itemNp: _s(json['itemNp']),
        codigoProducto: _s(json['codigoProducto']),
        producto: _s(json['producto']),
        proceso: _s(json['proceso']),
        maquina: _s(json['maquina']),
        operador: _s(json['operador']),
        estadoActual: json['estadoActual'] is Map<String, dynamic>
            ? EstadoPallet.fromJson(json['estadoActual'])
            : null,
      );

  /// Copia de los datos que viaja con la clasificación (el servidor los vuelve a consultar en FPS;
  /// solo se usa si FPS no responde al guardar).
  Map<String, dynamic> aDatosFps() => {
        'ordenFabricacion': ordenFabricacion,
        'npFaret': npFaret,
        'npInnpack': npInnpack,
        'cliente': cliente,
        'itemNp': itemNp,
        'codigoProducto': codigoProducto,
        'producto': producto,
        'proceso': proceso,
        'maquina': maquina,
        'operador': operador,
        'fechaTarja': fechaTarja,
        'cantidad': cantidad,
        'totalEtiquetas': totalEtiquetas,
      };
}

/// Un pallet ya clasificado dentro de la inspección en curso.
class PalletClasificado {
  final TarjaPallet tarja;
  final ColorPallet color;
  final Set<int> defectoIds;
  final String observacion;
  final Uint8List? fotoBytes;
  final String? fotoNombre;

  const PalletClasificado({
    required this.tarja,
    required this.color,
    this.defectoIds = const {},
    this.observacion = '',
    this.fotoBytes,
    this.fotoNombre,
  });
}

/// Estado de la sección "Clasificación de pallets" de una inspección. Se comparte entre las pantallas
/// del flujo (formulario -> mediciones) y arma lo que se envía junto con la inspección.
class ClasificacionPalletsController extends ChangeNotifier {
  final List<PalletClasificado> _items = [];

  List<PalletClasificado> get items => List.unmodifiable(_items);
  bool get estaVacio => _items.isEmpty;
  bool get llegoAlMaximo => _items.length >= maxPalletsPorInspeccion;

  int indiceDe(String codigo) =>
      _items.indexWhere((p) => p.tarja.codigo == codigo);

  /// Agrega el pallet o, si ya estaba en la lista, reemplaza su clasificación.
  void guardar(PalletClasificado pallet) {
    final i = indiceDe(pallet.tarja.codigo);
    if (i >= 0) {
      _items[i] = pallet;
    } else {
      _items.add(pallet);
    }
    notifyListeners();
  }

  void quitar(String codigo) {
    _items.removeWhere((p) => p.tarja.codigo == codigo);
    notifyListeners();
  }

  /// Resumen para mostrar, p. ej. "1 AZUL · 2 VERDE".
  String get resumen {
    final partes = <String>[];
    for (final c in ColorPallet.values) {
      final n = _items.where((p) => p.color == c).length;
      if (n > 0) partes.add('$n ${c.valor}');
    }
    return partes.join(' · ');
  }

  /// Las fotos no se guardan sin conexión (igual que la evidencia de la inspección).
  bool get tieneFotos => _items.any((p) => p.fotoBytes != null);

  /// Fotos en el orden en que `aPayload()` las referencia con `fotoIndex`.
  List<({Uint8List bytes, String nombre})> get fotos => [
        for (final p in _items)
          if (p.fotoBytes != null)
            (bytes: p.fotoBytes!, nombre: p.fotoNombre ?? 'pallet.jpg'),
      ];

  List<Map<String, dynamic>> aPayload() {
    var indiceFoto = 0;
    return [
      for (final p in _items)
        {
          'codigo': p.tarja.codigo,
          'color': p.color.valor,
          'defectos': p.defectoIds.toList()..sort(),
          'observacion':
              p.observacion.trim().isEmpty ? null : p.observacion.trim(),
          'fotoIndex': p.fotoBytes != null ? indiceFoto++ : null,
          if (p.tarja.conDatos) 'datosFps': p.tarja.aDatosFps(),
        },
    ];
  }
}
