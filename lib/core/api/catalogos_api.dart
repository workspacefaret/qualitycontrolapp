import 'api_client.dart';

class CatalogosApi {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> obtenerCatalogoOffline() async {
    final response = await _apiClient.get('/catalogos/offline');

    if (response is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response['data']);
    }

    throw Exception('Respuesta inválida catálogo offline');
  }

  Future<List<Map<String, dynamic>>> obtenerUsuarios() async {
    final response = await _apiClient.get('/catalogos/usuarios');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener usuarios');
  }

  Future<List<Map<String, dynamic>>> obtenerMaquinas() async {
    final response = await _apiClient.get('/catalogos/maquinas');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener máquinas');
  }

  /// [empresa] ('FARET') agrega los defectos propios de esa empresa; sin ella
  /// solo llegan los compartidos (lo que ve INNPACK y las apps anteriores).
  Future<List<Map<String, dynamic>>> obtenerParametrosVisuales(
    int procesoId, {
    String? empresa,
  }) async {
    final consulta = empresa == null ? '' : '?empresa=$empresa';
    final response = await _apiClient
        .get('/catalogos/parametros-visuales/$procesoId$consulta');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener parámetros visuales');
  }

  Future<List<Map<String, dynamic>>> obtenerOrigenesProblema(
    int procesoId,
  ) async {
    final response =
        await _apiClient.get('/catalogos/origenes-problema/$procesoId');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener orígenes del problema');
  }
}
