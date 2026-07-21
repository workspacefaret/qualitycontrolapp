import 'api_client.dart';

class CalidadFaretPalletApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<Map<String, dynamic>>> obtenerPreguntas() async {
    final response = await _apiClient.get('/calidad-faret-pallet/preguntas');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener preguntas');
  }

  Future<Map<String, dynamic>> guardarRegistro(
    Map<String, dynamic> payload,
  ) async {
    final response =
        await _apiClient.post('/calidad-faret-pallet/registros', payload);

    if (response is Map<String, dynamic> && response['ok'] == true) {
      return response;
    }

    throw Exception('Respuesta inválida al guardar registro');
  }
}
