import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class CalidadFaretApi {
  Future<Map<String, dynamic>> guardarRegistro(
    Map<String, dynamic> payload, {
    List<Uint8List> archivosBytes = const [],
    List<String> archivosNombres = const [],
  }) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/calidad-faret/registros');

    final request = http.MultipartRequest('POST', uri);

    request.fields['payload'] = jsonEncode(payload);

    for (var i = 0; i < archivosBytes.length; i++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'archivos',
          archivosBytes[i],
          filename:
              i < archivosNombres.length ? archivosNombres[i] : 'archivo_$i',
        ),
      );
    }

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
