import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/features/calidad_faret/domain/catalogo_planta_faret.dart';

void main() {
  test('fromJson lee áreas, máquinas y operadores', () {
    final c = CatalogoPlantaFaret.fromJson({
      'ok': true,
      'data': {
        'areas': [
          {'areaControl': '02-LAMINADO', 'nombre': 'LAMINADO'},
          {'areaControl': '10-PEGADO', 'nombre': 'PEGADO'},
        ],
        'maquinasPorArea': {
          '02-LAMINADO': ['SIRYUS', 'WEN CHYUAN'],
        },
        'operadoresPorArea': {
          '02-LAMINADO': ['ALAIN ESCORCIA'],
        },
      },
    });
    expect(c.areas, ['02-LAMINADO', '10-PEGADO']);
    expect(c.maquinasDe('02-LAMINADO'), ['SIRYUS', 'WEN CHYUAN']);
    expect(c.maquinasDe('10-PEGADO'), isEmpty);
  });

  test('operadoresDe agrega "Otros" una sola vez y al final', () {
    final c = CatalogoPlantaFaret.fromJson({
      'ok': true,
      'data': {
        'areas': [
          {'areaControl': 'A'},
        ],
        'maquinasPorArea': {},
        'operadoresPorArea': {
          'A': ['ZETA', 'Otros', 'ALFA'],
        },
      },
    });
    expect(c.operadoresDe('A'), ['ZETA', 'ALFA', 'Otros']);
    expect(c.operadoresDe(null), isEmpty);
  });

  test('respuesta inválida lanza FormatException', () {
    expect(
      () => CatalogoPlantaFaret.fromJson({'ok': false}),
      throwsFormatException,
    );
    expect(
      () => CatalogoPlantaFaret.fromJson({
        'ok': true,
        'data': {'areas': []},
      }),
      throwsFormatException,
    );
  });

  test('el respaldo conserva el catálogo compilado', () {
    expect(CatalogoPlantaFaret.respaldo.areas.length, 8);
    expect(
      CatalogoPlantaFaret.respaldo.maquinasDe('02-LAMINADO'),
      contains('WEN CHYUAN'),
    );
  });
}
