import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';
import '../local/offline_catalog_store.dart';

class ControlApi {
  final ApiClient _apiClient = ApiClient();
  final OfflineCatalogStore _offlineCatalogStore = OfflineCatalogStore();

  Future<Map<String, dynamic>> obtenerContextoPorQr(String codigoQr) async {
    final response = await _apiClient.get('/control/contexto/$codigoQr');

    if (response is Map<String, dynamic> &&
        response['data'] is Map<String, dynamic>) {
      return response['data'];
    }

    throw Exception('Respuesta inválida al obtener contexto QR');
  }

  Future<void> descargarCatalogoOffline() async {
    final response = await _apiClient.get(
      '/catalogos/offline',
    );

    if (response is Map<String, dynamic> &&
        response['data'] is Map<String, dynamic>) {
      await _offlineCatalogStore.saveCatalog(
        response['data'],
      );

      return;
    }

    throw Exception(
      'Respuesta inválida al descargar catálogo offline',
    );
  }

  Future<Map<String, dynamic>> guardarRegistro(
    Map<String, dynamic> payload, {
    Uint8List? archivoBytes,
    String? archivoNombre,
  }) async {
    if (archivoBytes == null) {
      final response = await _apiClient.post(
        '/control/registros',
        payload,
      );

      if (response is Map<String, dynamic> && response['ok'] == true) {
        return response;
      }

      throw Exception('Respuesta inválida al guardar registro');
    }

    final uri = Uri.parse('${ApiClient.baseUrl}/control/registros');

    final request = http.MultipartRequest('POST', uri);

    request.fields['payload'] = jsonEncode(payload);

    request.files.add(
      http.MultipartFile.fromBytes(
        'archivo',
        archivoBytes,
        filename: archivoNombre ?? 'archivo',
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic> && decoded['ok'] == true) {
        return decoded;
      }
    }

    throw Exception(
      'Error API (${response.statusCode}): ${response.body}',
    );
  }
}
