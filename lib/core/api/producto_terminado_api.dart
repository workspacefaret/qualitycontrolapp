import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class ProductoTerminadoApi {
  Future<Map<String, dynamic>> guardarRegistro(
    Map<String, dynamic> payload, {
    List<Uint8List> fotosBytes = const [],
    List<String> fotosNombres = const [],
  }) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/producto-terminado/registros');

    final request = http.MultipartRequest('POST', uri);

    request.fields['payload'] = jsonEncode(payload);

    for (var i = 0; i < fotosBytes.length; i++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'fotos',
          fotosBytes[i],
          filename: i < fotosNombres.length ? fotosNombres[i] : 'foto_$i.jpg',
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
