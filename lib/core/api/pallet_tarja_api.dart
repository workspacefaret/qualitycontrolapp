import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/clasificacion_pallets/domain/pallet_clasificacion.dart';
import 'api_client.dart';

/// Error al consultar una tarja, con un código estable para decidir qué mostrar.
class TarjaException implements Exception {
  /// CODIGO_INVALIDO, TARJA_NO_ENCONTRADA, TARJA_SIN_REGISTRO_PRODUCCION, FPS_NO_DISPONIBLE, SIN_CONEXION, ERROR
  final String codigo;
  final String mensaje;

  const TarjaException(this.codigo, this.mensaje);

  /// Errores en los que tiene sentido ofrecer clasificar solo con el código.
  bool get permiteSoloCodigo =>
      codigo == 'FPS_NO_DISPONIBLE' || codigo == 'SIN_CONEXION';

  @override
  String toString() => mensaje;
}

/// Una etiqueta del registro de producción (cuando el QR trae solo el número de registro).
class EtiquetaRegistro {
  final String codigo;
  final int nEtiqueta;
  final num? cantidad;

  const EtiquetaRegistro(this.codigo, this.nEtiqueta, this.cantidad);
}

/// Resultado de consultar un código: la tarja resuelta, o la lista de etiquetas para elegir.
class ResultadoTarja {
  final TarjaPallet? tarja;
  final List<EtiquetaRegistro> etiquetas;

  const ResultadoTarja.tarja(TarjaPallet t)
      : tarja = t,
        etiquetas = const [];
  const ResultadoTarja.elegir(this.etiquetas) : tarja = null;
}

class PalletTarjaApi {
  Future<ResultadoTarja> consultar(String codigo) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(
                '${ApiClient.baseUrl}/pallets/tarja/${Uri.encodeComponent(codigo.trim())}'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const TarjaException(
          'SIN_CONEXION', 'Sin conexión con el servidor. Intente nuevamente.');
    }

    Map<String, dynamic>? cuerpo;
    try {
      final d = jsonDecode(response.body);
      if (d is Map<String, dynamic>) cuerpo = d;
    } catch (_) {}

    if (response.statusCode == 200 && cuerpo?['data'] is Map<String, dynamic>) {
      final data = cuerpo!['data'] as Map<String, dynamic>;
      if (data['requiereEtiqueta'] == true) {
        final lista = (data['etiquetas'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => EtiquetaRegistro(
                  e['codigo'].toString(),
                  (e['nEtiqueta'] as num).toInt(),
                  e['cantidad'] is num ? e['cantidad'] as num : null,
                ))
            .toList();
        return ResultadoTarja.elegir(lista);
      }
      return ResultadoTarja.tarja(TarjaPallet.fromJson(data));
    }

    throw TarjaException(
      cuerpo?['code']?.toString() ?? 'ERROR',
      cuerpo?['message']?.toString() ??
          'No se pudo consultar la tarja. Intente nuevamente.',
    );
  }
}
