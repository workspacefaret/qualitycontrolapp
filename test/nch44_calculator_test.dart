import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/features/producto_terminado/domain/nch44_calculator.dart';

// Nota: Tabla 1 se testea vía letraTabla1() directamente (no vía
// calcularPlanMuestreo con un AQL fijo), porque un AQL fijo dispara las
// reglas de flecha de Tabla 2-A para las letras extremas (A/B/C, Q/R),
// lo que sustituye la letra cruda de Tabla 1 por la letra redirigida y
// hace que un test así falle sin que Tabla 1 tenga ningún error real.

void main() {
  group('calcularPlanMuestreo - caso de validación confirmado por el usuario', () {
    test('lote=20000, nivel=II, AQL=1.5 => letra M, muestra 315, Ac=10, Re=11', () {
      final plan = calcularPlanMuestreo(20000, 'II', 1.5);

      expect(plan.letraCodigo, 'M');
      expect(plan.tamanoMuestra, 315);
      expect(plan.ac, 10);
      expect(plan.re, 11);
      expect(plan.inspeccion100, isFalse);
    });

    test('lote=20000, nivel=II, AQL=4.0 => letra M, muestra 315, Ac=21, Re=22', () {
      final plan = calcularPlanMuestreo(20000, 'II', 4.0);

      expect(plan.letraCodigo, 'M');
      expect(plan.tamanoMuestra, 315);
      expect(plan.ac, 21);
      expect(plan.re, 22);
      expect(plan.inspeccion100, isFalse);
    });
  });

  group('calcularPlanMuestreo - Tabla 1 completa (letra por lote, I/II/III)', () {
    // Tabla 1 - Letras código del tamaño de muestra (niveles generales I/II/III),
    // valores tomados literalmente del requerimiento, no derivados del código.
    const casos = <List<Object?>>[
      [2, 8, 'A', 'A', 'B'],
      [9, 15, 'A', 'B', 'C'],
      [16, 25, 'B', 'C', 'D'],
      [26, 50, 'C', 'D', 'E'],
      [51, 90, 'C', 'E', 'F'],
      [91, 150, 'D', 'F', 'G'],
      [151, 280, 'E', 'G', 'H'],
      [281, 500, 'F', 'H', 'J'],
      [501, 1200, 'G', 'J', 'K'],
      [1201, 3200, 'H', 'K', 'L'],
      [3201, 10000, 'J', 'L', 'M'],
      [10001, 35000, 'K', 'M', 'N'],
      [35001, 150000, 'L', 'N', 'P'],
      [150001, 500000, 'M', 'P', 'Q'],
      [500001, 5000000, 'N', 'Q', 'R'], // 500001 y mayor (sin límite superior)
    ];

    for (final caso in casos) {
      final loteMin = caso[0] as int;
      final loteMax = caso[1] as int;
      final nivelI = caso[2] as String;
      final nivelII = caso[3] as String;
      final nivelIII = caso[4] as String;

      test('lote $loteMin-$loteMax => I=$nivelI, II=$nivelII, III=$nivelIII', () {
        for (final lote in [loteMin, loteMax]) {
          expect(letraTabla1(lote, 'I'), nivelI);
          expect(letraTabla1(lote, 'II'), nivelII);
          expect(letraTabla1(lote, 'III'), nivelIII);
        }
      });
    }
  });

  group('calcularPlanMuestreo - regla de flecha e inspección 100%', () {
    test('muestra >= lote => inspección 100%, sin Ac/Re', () {
      // lote=2 -> letra A/A/B, muestra letra A = 2 = tamaño del lote.
      final plan = calcularPlanMuestreo(2, 'I', 1.0);

      expect(plan.inspeccion100, isTrue);
      expect(plan.ac, isNull);
      expect(plan.re, isNull);
    });

    test('regla de flecha hacia abajo (▽): usa el plan de una letra mayor', () {
      // lote=1200, nivel I => letra G, AQL=0.15 requiere una muestra mayor.
      final plan = calcularPlanMuestreo(1200, 'I', 0.15);

      expect(plan.letraCodigo, 'L');
      expect(plan.tamanoMuestra, 200);
      expect(plan.ac, 0);
      expect(plan.re, 1);
      expect(plan.inspeccion100, isFalse);
      expect(plan.notaFlecha, contains('↓'));
    });

    test('regla de flecha hacia arriba (△): usa el plan de una letra menor', () {
      // lote=1200, nivel III => letra K, AQL=650 (muy laxo) permite muestra menor.
      final plan = calcularPlanMuestreo(1200, 'III', 650);

      expect(plan.letraCodigo, 'C');
      expect(plan.tamanoMuestra, 5);
      expect(plan.ac, 44);
      expect(plan.re, 45);
      expect(plan.inspeccion100, isFalse);
      expect(plan.notaFlecha, contains('↑'));
    });

    test('flecha hacia abajo cuyo destino ya excede el lote => inspección 100%', () {
      // lote=8, nivel I => letra A, AQL=0.65 redirige a letra H (muestra 50) >= lote.
      final plan = calcularPlanMuestreo(8, 'I', 0.65);

      expect(plan.inspeccion100, isTrue);
      expect(plan.ac, isNull);
      expect(plan.re, isNull);
    });

    test('AQL no incluido en Tabla 2-A lanza error en vez de inventar', () {
      expect(() => calcularPlanMuestreo(1000, 'I', 3.0), throwsArgumentError);
    });
  });
}
