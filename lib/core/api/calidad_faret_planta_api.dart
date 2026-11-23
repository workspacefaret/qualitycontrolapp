import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/calidad_faret/domain/catalogo_planta_faret.dart';
import 'api_client.dart';

/// Descarga el catálogo de planta (áreas, máquinas, operadores) y lo guarda
/// localmente. Orden de preferencia: servidor → última copia válida → catálogo
/// compilado en la app. Nunca lanza: el formulario siempre tiene con qué trabajar.
class CalidadFaretPlantaApi {
  static const String _cacheKey = 'calidad_faret_catalogo_planta_v1';

  Future<CatalogoPlantaFaret> obtenerCatalogo() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/calidad-faret/catalogo-planta'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final catalogo = CatalogoPlantaFaret.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        await _guardarCache(body);
        return catalogo;
      }
    } catch (_) {
      // Cae a la copia local.
    }

    return await _leerCache() ?? CatalogoPlantaFaret.respaldo;
  }

  Future<void> _guardarCache(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
    } catch (_) {}
  }

  Future<CatalogoPlantaFaret?> _leerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_cacheKey);
      if (body == null) return null;
      return CatalogoPlantaFaret.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
