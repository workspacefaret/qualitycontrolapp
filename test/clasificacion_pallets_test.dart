import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/core/api/pallet_tarja_api.dart';
import 'package:quality_control/features/clasificacion_pallets/domain/pallet_clasificacion.dart';
import 'package:quality_control/features/clasificacion_pallets/presentation/clasificacion_pallets_section.dart';

TarjaPallet _tarja(String codigo, {EstadoPallet? estado}) => TarjaPallet(
      codigo: codigo,
      totalEtiquetas: 25,
      cantidad: 1200,
      fechaTarja: '2026-11-22T21:08:49',
      ordenFabricacion: '22669',
      npFaret: '22669',
      npInnpack: '3957',
      cliente: 'INNPACK SpA-A.G. SERVICIOS SPA',
      producto: 'PLIEGO TROQUELADO',
      proceso: 'TROQUEL',
      maquina: 'BOBST 142 - 2 (SFM)',
      operador: 'LUIS MONTOYA',
      estadoActual: estado,
    );

class _ApiFalsa extends PalletTarjaApi {
  final Map<String, ResultadoTarja> respuestas;
  final Object? error;
  final List<String> consultas = [];

  _ApiFalsa({this.respuestas = const {}, this.error});

  @override
  Future<ResultadoTarja> consultar(String codigo) async {
    consultas.add(codigo);
    if (error != null) throw error!;
    final r = respuestas[codigo];
    if (r == null) {
      throw const TarjaException('TARJA_NO_ENCONTRADA', 'No se encontró esa tarja.');
    }
    return r;
  }
}

const _parametros = [
  {'id': 1, 'nombre': 'Descalse', 'criticidad': 'mayor'},
  {'id': 2, 'nombre': 'Rayado', 'criticidad': 'menor'},
];

Future<ClasificacionPalletsController> _montar(
  WidgetTester tester, {
  required PalletTarjaApi api,
  String? Function()? lectura,
  Set<String> preseleccion = const {},
  Future<FotoSeleccionada?> Function()? foto,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = ClasificacionPalletsController();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ClasificacionPalletsSection(
          controller: controller,
          parametrosVisuales: _parametros,
          defectosPreseleccionados: () => preseleccion,
          api: api,
          lector: lectura == null ? null : (_) async => lectura(),
          selectorFoto: foto,
        ),
      ),
    ),
  ));
  return controller;
}

Future<void> _escribirCodigo(WidgetTester tester, String codigo) async {
  await tester.tap(find.text('Escribir código'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), codigo);
  await tester.tap(find.text('Buscar'));
  await tester.pumpAndSettle();
}

void main() {
  group('Modelo y controlador', () {
    test('validación del código de tarja (pallet o registro) e inyecciones', () {
      expect(esCodigoTarjaValido('466568-1'), isTrue);
      expect(esCodigoTarjaValido(' 466568-12 '), isTrue);
      expect(esCodigoTarjaValido('466568'), isTrue);
      expect(esCodigoPallet('466568'), isFalse);
      for (final malo in ["1' OR '1'='1", '466568-', 'FPS-OF-22669', '', '12-34-56', '466568-1;x']) {
        expect(esCodigoTarjaValido(malo), isFalse, reason: malo);
      }
    });

    test('payload: colores, defectos ordenados, observación nula si vacía y fotoIndex correlativo', () {
      final c = ClasificacionPalletsController();
      c.guardar(PalletClasificado(
        tarja: _tarja('1-1'),
        color: ColorPallet.azul,
        defectoIds: {3, 1},
        observacion: '  revisar ',
        fotoBytes: Uint8List.fromList([1]),
        fotoNombre: 'a.jpg',
      ));
      c.guardar(PalletClasificado(tarja: _tarja('1-2'), color: ColorPallet.verde));
      c.guardar(PalletClasificado(
        tarja: const TarjaPallet.soloCodigo('1-3'),
        color: ColorPallet.rojo,
        fotoBytes: Uint8List.fromList([2]),
        fotoNombre: 'b.jpg',
      ));

      final p = c.aPayload();
      expect(p.map((e) => e['color']), ['AZUL', 'VERDE', 'ROJO']);
      expect(p[0]['defectos'], [1, 3]);
      expect(p[0]['observacion'], 'revisar');
      expect(p[1]['observacion'], isNull);
      expect(p.map((e) => e['fotoIndex']), [0, null, 1]);
      expect(p[0].containsKey('datosFps'), isTrue);
      expect(p[2].containsKey('datosFps'), isFalse, reason: 'sin datos de FPS no se envía copia');
      expect(c.fotos.map((f) => f.nombre), ['a.jpg', 'b.jpg']);
      expect(c.tieneFotos, isTrue);
      expect(c.resumen, '1 AZUL · 1 ROJO · 1 VERDE');
    });

    test('un pallet repetido se reemplaza (reclasificación dentro de la inspección), no se duplica', () {
      final c = ClasificacionPalletsController();
      c.guardar(PalletClasificado(tarja: _tarja('1-1'), color: ColorPallet.azul));
      c.guardar(PalletClasificado(tarja: _tarja('1-1'), color: ColorPallet.verde));
      expect(c.items, hasLength(1));
      expect(c.items.single.color, ColorPallet.verde);
      c.quitar('1-1');
      expect(c.estaVacio, isTrue);
    });

    test('sin pallets el payload queda vacío y sin fotos', () {
      final c = ClasificacionPalletsController();
      expect(c.aPayload(), isEmpty);
      expect(c.fotos, isEmpty);
      expect(c.tieneFotos, isFalse);
    });

    test('TarjaPallet.fromJson tolera campos faltantes y nulos', () {
      final t = TarjaPallet.fromJson({
        'codigo': '466568-1',
        'cantidad': null,
        'cliente': '  ',
        'estadoActual': {'id': 7, 'color': 'AZUL', 'clasificadoEn': '2026-11-23T10:30:00'},
      });
      expect(t.cantidad, isNull);
      expect(t.cliente, isNull);
      expect(t.estadoActual!.color, ColorPallet.azul);
    });

    test('TarjaException: solo FPS caído / sin conexión permiten clasificar con el código', () {
      expect(const TarjaException('FPS_NO_DISPONIBLE', 'x').permiteSoloCodigo, isTrue);
      expect(const TarjaException('SIN_CONEXION', 'x').permiteSoloCodigo, isTrue);
      expect(const TarjaException('TARJA_NO_ENCONTRADA', 'x').permiteSoloCodigo, isFalse);
    });
  });

  group('Sección en el formulario', () {
    testWidgets('inspección sin pallets: la sección es opcional y no muestra nada guardado', (tester) async {
      final c = await _montar(tester, api: _ApiFalsa());
      expect(find.text('Clasificación de pallets'), findsOneWidget);
      expect(find.text('Escanear tarja de pallet'), findsOneWidget);
      expect(c.estaVacio, isTrue);
    });

    testWidgets('flujo mínimo: escribir código, tocar AZUL y guardar (datos de FPS visibles)', (tester) async {
      final api = _ApiFalsa(respuestas: {'466568-1': ResultadoTarja.tarja(_tarja('466568-1'))});
      final c = await _montar(tester, api: api);

      await _escribirCodigo(tester, '466568-1');
      expect(find.text('Pallet 466568-1'), findsOneWidget);
      expect(find.textContaining('INNPACK SpA-A.G. SERVICIOS SPA'), findsOneWidget);
      expect(find.textContaining('BOBST 142 - 2 (SFM)'), findsOneWidget);
      expect(find.textContaining('1.200 un'), findsOneWidget);
      expect(find.textContaining('22/11/2026 21:08'), findsOneWidget);
      expect(find.text('ELIJA AZUL, ROJO O VERDE'), findsOneWidget);

      await tester.tap(find.text('AZUL'));
      await tester.pump();
      await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
      await tester.pumpAndSettle();

      expect(c.items, hasLength(1));
      expect(c.items.single.color, ColorPallet.azul);
      expect(c.items.single.observacion, '');
      expect(c.items.single.fotoBytes, isNull, reason: 'la foto es opcional');
      expect(c.items.single.defectoIds, isEmpty, reason: 'los defectos son opcionales');
      expect(find.text('1 AZUL'), findsOneWidget);
      expect(find.text('Escanear otro pallet'), findsOneWidget);
    });

    testWidgets('los tres colores se pueden guardar y VERDE descarta defectos', (tester) async {
      final api = _ApiFalsa(respuestas: {
        '1-1': ResultadoTarja.tarja(_tarja('1-1')),
        '1-2': ResultadoTarja.tarja(_tarja('1-2')),
        '1-3': ResultadoTarja.tarja(_tarja('1-3')),
      });
      final c = await _montar(tester, api: api, preseleccion: {'1'});

      for (final par in [('1-1', 'AZUL'), ('1-2', 'ROJO'), ('1-3', 'VERDE')]) {
        await _escribirCodigo(tester, par.$1);
        await tester.tap(find.text(par.$2).last);
        await tester.pump();
        await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
        await tester.pumpAndSettle();
      }

      expect(c.items.map((p) => p.color.valor), ['AZUL', 'ROJO', 'VERDE']);
      expect(c.items[0].defectoIds, {1}, reason: 'AZUL conserva el defecto preseleccionado de la inspección');
      expect(c.items[2].defectoIds, isEmpty);
      expect(c.resumen, '1 AZUL · 1 ROJO · 1 VERDE');
    });

    testWidgets('defectos, observación y foto opcionales se guardan cuando se usan', (tester) async {
      final api = _ApiFalsa(respuestas: {'1-1': ResultadoTarja.tarja(_tarja('1-1'))});
      final c = await _montar(
        tester,
        api: api,
        foto: () async => (bytes: Uint8List.fromList([9, 9]), nombre: 'p.jpg'),
      );

      await _escribirCodigo(tester, '1-1');
      await tester.tap(find.text('ROJO'));
      await tester.pump();
      await tester.tap(find.text('Rayado'));
      await tester.enterText(find.byType(TextField), 'golpe en esquina');
      await tester.tap(find.text('Agregar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Cambiar foto'), findsOneWidget);
      await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
      await tester.pumpAndSettle();

      final p = c.items.single;
      expect(p.defectoIds, {2});
      expect(p.observacion, 'golpe en esquina');
      expect(p.fotoBytes, isNotNull);
      expect(c.aPayload().single['fotoIndex'], 0);
    });

    testWidgets('al reescanear un pallet con clasificación vigente se avisa y se puede reclasificar', (tester) async {
      final api = _ApiFalsa(respuestas: {
        '1-1': ResultadoTarja.tarja(_tarja('1-1',
            estado: const EstadoPallet(color: ColorPallet.azul, clasificadoEn: '2026-11-21T14:30:00'))),
      });
      final c = await _montar(tester, api: api);

      await _escribirCodigo(tester, '1-1');
      expect(find.textContaining('Actualmente AZUL desde 21/11/2026 14:30'), findsOneWidget);
      await tester.tap(find.text('VERDE'));
      await tester.pump();
      await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
      await tester.pumpAndSettle();
      expect(c.items.single.color, ColorPallet.verde);
    });

    testWidgets('el lector (QR) entrega el código y abre la clasificación', (tester) async {
      final api = _ApiFalsa(respuestas: {'466568-2': ResultadoTarja.tarja(_tarja('466568-2'))});
      await _montar(tester, api: api, lectura: () => '466568-2');
      await tester.tap(find.text('Escanear tarja de pallet'));
      await tester.pumpAndSettle();
      expect(api.consultas, ['466568-2']);
      expect(find.text('Pallet 466568-2'), findsOneWidget);
    });

    testWidgets('QR de otro tipo: mensaje claro y sin consultar al servidor', (tester) async {
      final api = _ApiFalsa();
      final c = await _montar(tester, api: api, lectura: () => 'FPS-OF-22669');
      await tester.tap(find.text('Escanear tarja de pallet'));
      await tester.pumpAndSettle();
      expect(find.text('Este código no corresponde a una tarja de pallet.'), findsOneWidget);
      expect(api.consultas, isEmpty);
      expect(c.estaVacio, isTrue);
    });

    testWidgets('tarja inexistente: mensaje del servidor y la inspección sigue sin pallets', (tester) async {
      final c = await _montar(tester, api: _ApiFalsa());
      await _escribirCodigo(tester, '999-9');
      expect(find.text('No se encontró esa tarja.'), findsOneWidget);
      expect(c.estaVacio, isTrue);
    });

    testWidgets('solo número de registro con varias etiquetas: se elige el pallet', (tester) async {
      final api = _ApiFalsa(respuestas: {
        '555': const ResultadoTarja.elegir([EtiquetaRegistro('555-1', 1, null), EtiquetaRegistro('555-2', 2, 300)]),
        '555-2': ResultadoTarja.tarja(_tarja('555-2')),
      });
      await _montar(tester, api: api);
      await _escribirCodigo(tester, '555');
      expect(find.text('¿Qué pallet?'), findsOneWidget);
      await tester.tap(find.text('N° 2 (300 un)'));
      await tester.pumpAndSettle();
      expect(api.consultas, ['555', '555-2']);
      expect(find.text('Pallet 555-2'), findsOneWidget);
    });

    testWidgets('FPS caído: se ofrece clasificar solo con el código y se marca sin datos', (tester) async {
      final api = _ApiFalsa(error: const TarjaException('FPS_NO_DISPONIBLE', 'No se pudo consultar el sistema de producción.'));
      final c = await _montar(tester, api: api);

      await _escribirCodigo(tester, '466568-1');
      expect(find.textContaining('No se pudo consultar el sistema de producción.'), findsOneWidget);
      await tester.tap(find.text('Clasificar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin datos de producción por ahora'), findsOneWidget);

      await tester.tap(find.text('VERDE'));
      await tester.pump();
      await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
      await tester.pumpAndSettle();
      expect(c.items.single.tarja.conDatos, isFalse);
      expect(c.aPayload().single.containsKey('datosFps'), isFalse);
    });

    testWidgets('se puede quitar un pallet de la lista', (tester) async {
      final api = _ApiFalsa(respuestas: {'1-1': ResultadoTarja.tarja(_tarja('1-1'))});
      final c = await _montar(tester, api: api);
      await _escribirCodigo(tester, '1-1');
      await tester.tap(find.text('AZUL'));
      await tester.pump();
      await tester.tap(find.text('GUARDAR CLASIFICACIÓN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quitar'));
      await tester.pumpAndSettle();
      expect(c.estaVacio, isTrue);
    });
  });
}
