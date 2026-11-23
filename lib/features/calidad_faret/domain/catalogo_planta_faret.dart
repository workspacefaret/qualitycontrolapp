import 'calidad_faret_catalog.dart';

/// Áreas, máquinas y operadores de máquina vigentes de Calidad FARET, administrados
/// desde el QCC y servidos por `GET /api/calidad-faret/catalogo-planta`. Si no hay
/// red ni copia local, la app usa [respaldo] (lo que traía compilado).
class CatalogoPlantaFaret {
  final List<String> areas;
  final Map<String, List<String>> operadoresPorArea;
  final Map<String, List<String>> maquinasPorArea;

  const CatalogoPlantaFaret({
    required this.areas,
    required this.operadoresPorArea,
    required this.maquinasPorArea,
  });

  static const CatalogoPlantaFaret respaldo = CatalogoPlantaFaret(
    areas: CalidadFaretCatalog.areasControl,
    operadoresPorArea: CalidadFaretCatalog.operadoresPorArea,
    maquinasPorArea: CalidadFaretCatalog.maquinasPorArea,
  );

  static const String _otros = 'Otros';

  /// Operadores del área; "Otros" siempre va al final (permite escribir uno nuevo).
  List<String> operadoresDe(String? area) {
    if (area == null) return const [];
    return [...?operadoresPorArea[area]?.where((n) => n != _otros), _otros];
  }

  List<String> maquinasDe(String? area) => maquinasPorArea[area] ?? const [];

  factory CatalogoPlantaFaret.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (json['ok'] != true || data is! Map<String, dynamic>) {
      throw const FormatException('Catálogo de planta inválido');
    }
    final areasJson = data['areas'];
    if (areasJson is! List || areasJson.isEmpty) {
      throw const FormatException('Catálogo de planta sin áreas');
    }

    Map<String, List<String>> porArea(Object? valor) {
      if (valor is! Map) return const {};
      return valor.map(
        (area, nombres) => MapEntry(
          area.toString(),
          (nombres as List).map((n) => n.toString()).toList(),
        ),
      );
    }

    return CatalogoPlantaFaret(
      areas: areasJson
          .map((a) => (a as Map<String, dynamic>)['areaControl'].toString())
          .toList(),
      operadoresPorArea: porArea(data['operadoresPorArea']),
      maquinasPorArea: porArea(data['maquinasPorArea']),
    );
  }
}
