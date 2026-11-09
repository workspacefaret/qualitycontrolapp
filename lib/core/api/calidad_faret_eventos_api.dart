import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/calidad_faret/domain/catalogo_eventos_faret.dart';
import 'api_client.dart';

class CatalogoEventosResultado {
  final CatalogoEventosFaret catalogo;
  final bool desdeCache;

  const CatalogoEventosResultado(this.catalogo, {required this.desdeCache});
}

/// Descarga el catálogo oficial de eventos y lo guarda localmente. Si la red o
/// el servidor fallan, usa la última copia válida; si no hay ninguna, lanza.
class CalidadFaretEventosApi {
  static const String _cacheKey = 'calidad_faret_catalogo_eventos_v1';

  Future<CatalogoEventosResultado> obtenerCatalogo() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiClient.baseUrl}/calidad-faret/catalogo-eventos'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final catalogo = CatalogoEventosFaret.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        await _guardarCache(body);
        return CatalogoEventosResultado(catalogo, desdeCache: false);
      }
    } catch (_) {
      // Cae a la copia local.
    }

    final cacheado = await _leerCache();
    if (cacheado != null) {
      return CatalogoEventosResultado(cacheado, desdeCache: true);
    }
    throw Exception('Catálogo de eventos no disponible');
  }

  Future<void> _guardarCache(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, body);
    } catch (_) {}
  }

  Future<CatalogoEventosFaret?> _leerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString(_cacheKey);
      if (body == null) return null;
      return CatalogoEventosFaret.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
