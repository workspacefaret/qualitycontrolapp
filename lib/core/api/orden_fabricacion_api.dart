import 'api_client.dart';

class OrdenFabricacionApi {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> obtenerOrdenFabricacion(
    String np, {
    String? proceso,
  }) async {
    final query = proceso == null || proceso.isEmpty
        ? ''
        : '?proceso=${Uri.encodeQueryComponent(proceso)}';

    final response = await _apiClient.get('/orden-fabricacion/$np$query');

    if (response is Map<String, dynamic> &&
        response['data'] is Map<String, dynamic>) {
      return response['data'];
    }

    throw Exception('Respuesta inválida al consultar orden de fabricación');
  }
}
