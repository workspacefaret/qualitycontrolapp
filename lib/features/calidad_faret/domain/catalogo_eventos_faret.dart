/// Catálogo oficial de eventos (defectos) de Calidad FARET, servido por
/// `GET /api/calidad-faret/catalogo-eventos`. El backend solo entrega eventos
/// operables; la app nunca decide por sí misma qué evento está habilitado.
class EventoFaret {
  final String idEvento;
  final String defecto;
  final String criticidad;

  const EventoFaret({
    required this.idEvento,
    required this.defecto,
    required this.criticidad,
  });

  factory EventoFaret.fromJson(Map<String, dynamic> json) => EventoFaret(
        idEvento: json['idEvento'].toString(),
        defecto: json['defecto'].toString(),
        criticidad: (json['criticidad'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'idEvento': idEvento,
        'defecto': defecto,
        'criticidad': criticidad,
      };
}

class AreaEventosFaret {
  final String codArea;
  final String areaControl;
  final List<EventoFaret> eventos;

  const AreaEventosFaret({
    required this.codArea,
    required this.areaControl,
    required this.eventos,
  });
}

class CatalogoEventosFaret {
  final String version;
  final List<AreaEventosFaret> areas;

  const CatalogoEventosFaret({required this.version, required this.areas});

  /// Lanza [FormatException] si la estructura no es la esperada.
  factory CatalogoEventosFaret.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (json['ok'] != true || data is! Map<String, dynamic>) {
      throw const FormatException('Catálogo de eventos inválido');
    }
    final areasJson = data['areas'];
    if (areasJson is! List) {
      throw const FormatException('Catálogo de eventos sin áreas');
    }

    final areas = areasJson.map((a) {
      final m = a as Map<String, dynamic>;
      final eventos = (m['eventos'] as List)
          .map((e) => EventoFaret.fromJson(e as Map<String, dynamic>))
          .toList();
      return AreaEventosFaret(
        codArea: m['codArea'].toString(),
        areaControl: m['areaControl'].toString(),
        eventos: eventos,
      );
    }).toList();

    return CatalogoEventosFaret(
      version: (data['version'] ?? '').toString(),
      areas: areas,
    );
  }

  /// Nombres de área (`areaControl`) que tienen al menos un evento operable.
  List<String> get areasConEventos => areas
      .where((a) => a.eventos.isNotEmpty)
      .map((a) => a.areaControl)
      .toList();

  List<EventoFaret> eventosDe(String? areaControl) {
    for (final a in areas) {
      if (a.areaControl == areaControl) return a.eventos;
    }
    return const [];
  }
}
