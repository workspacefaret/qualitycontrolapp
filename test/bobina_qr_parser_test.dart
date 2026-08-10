import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/features/control_form/domain/bobina_qr_parser.dart';

void main() {
  group('parseBobinaQr - pesos documentados en consumo_papel/qr_parser.php', () {
    // Casos tomados literalmente de los comentarios de helpers/qr_parser.php
    // (detectar_peso_inteligente). Los 2 primeros (caso "con coma") coinciden
    // exactamente con el peso comentado en el PHP original. Los 4 restantes
    // (caso "sin coma", 2 decimales implicitos) NO coinciden con el peso que
    // dice el comentario del PHP (20/120/180/5) — se verificó ejecutando el
    // algoritmo real (public/qr_scan.js, extraerPesoQR) sin modificar contra
    // estos mismos strings: el resultado real es 0.02/0.12/0.18/0.05, no el
    // valor del comentario. El comentario del PHP quedó desactualizado
    // respecto al código; este test verifica fidelidad al ALGORITMO real
    // (lo que efectivamente corre en producción), no al comentario.
    const casos = <String, double>{
      '0211700029300130371188,000103389-3#911000021': 1188,
      '021145003801010337850,0000104601-7#911000076': 850,
      '020411100811812137000020001072450-1#9121394': 0.02,
      '02040010010019573700012000107450-2#9121690': 0.12,
      '020400100100045537000180001073540-4#9121572': 0.18,
      '020454201304554137000005001074798-5#913692': 0.05,
    };

    casos.forEach((qr, pesoEsperado) {
      test('$qr -> peso $pesoEsperado', () {
        final result = parseBobinaQr(qr);
        expect(result.tarjaKg, pesoEsperado);
        expect(result.lote, isNotNull);
      });
    });
  });

  group('parseBobinaQr - casos especiales', () {
    test('excepcion hardcodeada AJUSTE MAYO 2026', () {
      final result = parseBobinaQr('AJUSTE MAYO 2026');
      expect(result.lote, 'AJUSTE  MAYO 2026');
    });

    test('QR de excepcion con | no calcula peso', () {
      final result = parseBobinaQr('...#911000037|31105834021319');
      expect(result.tarjaKg, isNull);
    });

    test('codigo de barra 1D limpio se usa como lote directo', () {
      final result = parseBobinaQr('T010128343');
      expect(result.lote, 'T010128343');
      expect(result.tarjaKg, isNull);
    });

    test('docnum se extrae despues de #', () {
      final result = parseBobinaQr('020454201304554137000005001074798-5#913692');
      expect(result.docnum, '913692');
    });

    test('string vacio no rompe nada', () {
      final result = parseBobinaQr('');
      expect(result.lote, isNull);
      expect(result.docnum, isNull);
      expect(result.tarjaKg, isNull);
    });
  });

  group('detectarPesoInteligente - bug del strrpos/lastIndexOf', () {
    test('usa la ULTIMA ocurrencia de 37, no la primera', () {
      // Codigo de articulo "999371233700762,0005277-1": trae un "37" casual
      // en el codigo de articulo (999-37-1233) ANTES del marcador real de
      // peso. Tomar la primera ocurrencia de "37" (bug historico corregido
      // en consumo_papel) calcularia un peso disparatado a partir de
      // "1233700762..."; tomar la ULTIMA (correcto) da el peso real: 762.
      final conBasura = '9993712337000762,0005277-1';
      final resultado = detectarPesoInteligente(conBasura);

      expect(resultado, 762.0);
    });
  });
}
