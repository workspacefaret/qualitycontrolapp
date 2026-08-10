import 'api_client.dart';

class BobinaApi {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, dynamic>> resolverPorLote(String lote) async {
    final response = await _apiClient.get('/bobina/lote/${Uri.encodeComponent(lote)}');

    if (response is Map<String, dynamic> &&
        response['data'] is Map<String, dynamic>) {
      return response['data'];
    }

    throw Exception('Respuesta inválida al resolver bobina por lote');
  }
}
