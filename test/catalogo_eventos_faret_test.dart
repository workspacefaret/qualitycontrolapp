import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/features/calidad_faret/domain/catalogo_eventos_faret.dart';

void main() {
  final json = {
    'ok': true,
    'data': {
      'version': 'abc',
      'areas': [
        {
          'codArea': 'LAM',
          'areaControl': '02-LAMINADO',
          'eventos': [
            {'idEvento': 'LAM-001', 'defecto': 'Defecto de anclaje.', 'criticidad': 'Critico'},
            {'idEvento': 'LAM-003', 'defecto': 'Traslape.', 'criticidad': 'Menor'},
          ],
        },
        {'codArea': 'CYD', 'areaControl': '13-CORTE Y DIMENSIONADO', 'eventos': []},
      ],
    },
  };

  test('parsea el catálogo y filtra por área', () {
    final c = CatalogoEventosFaret.fromJson(json);
    expect(c.version, 'abc');
    expect(c.eventosDe('02-LAMINADO').map((e) => e.idEvento), ['LAM-001', 'LAM-003']);
    expect(c.eventosDe('02-LAMINADO').first.criticidad, 'Critico');
    expect(c.eventosDe('NO-EXISTE'), isEmpty);
    expect(c.eventosDe(null), isEmpty);
  });

  test('áreas sin eventos operables no se ofrecen', () {
    expect(CatalogoEventosFaret.fromJson(json).areasConEventos, ['02-LAMINADO']);
  });

  test('estructura inválida lanza FormatException', () {
    expect(() => CatalogoEventosFaret.fromJson({'ok': false}), throwsFormatException);
    expect(() => CatalogoEventosFaret.fromJson({'ok': true, 'data': {'areas': 1}}), throwsFormatException);
  });
}
