import 'api_client.dart';

class CalidadFaretOperadoresApi {
  final ApiClient _apiClient = ApiClient();

  Future<List<String>> obtenerOperadores() async {
    final response = await _apiClient.get('/calidad-faret/operadores');

    if (response is Map<String, dynamic> && response['data'] is List) {
      return List<String>.from(response['data']);
    }

    throw Exception('Respuesta inválida al obtener operadores');
  }
}
