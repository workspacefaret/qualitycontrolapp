import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/core/local/pending_records_store.dart';
import 'package:quality_control/core/utils/client_id.dart';
import 'package:quality_control/core/widgets/evidencia_miniatura.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PNG válido de 1x1 píxel.
final Uint8List _png1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
  0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clientId (idempotencia de envíos)', () {
    test('cumple el formato que valida el backend y no se repite', () {
      final ids = List.generate(200, (_) => generarClientId());
      final formatoBackend = RegExp(r'^[A-Za-z0-9-]{8,36}$');

      expect(ids.every(formatoBackend.hasMatch), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('un registro pendiente offline conserva su clientId para reintentos sin duplicar', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingRecordsStore();
      final id = generarClientId();

      await store.savePendingRecord({'procesoId': 3, 'maquinaId': 6, 'clientId': id});

      final pendientes = await store.getPendingRecords();
      expect(pendientes.single['payload']['clientId'], id);
    });

    test('un registro pendiente de un APK anterior (sin clientId) sigue siendo legible', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingRecordsStore();

      await store.savePendingRecord({'procesoId': 3, 'maquinaId': 6});

      final payload = (await store.getPendingRecords()).single['payload'] as Map;
      expect(payload.containsKey('clientId'), isFalse);
    });
  });

  group('EvidenciaMiniatura (vista previa antes de guardar)', () {
    Future<void> montar(WidgetTester tester, String nombre) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EvidenciaMiniatura(bytes: _png1x1, nombre: nombre),
          ),
        ),
      );
    }

    testWidgets('una foto JPG/PNG muestra la imagen', (tester) async {
      await montar(tester, 'densitometria.png');

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf), findsNothing);
    });

    testWidgets('un PDF muestra el ícono, sin intentar decodificarlo', (tester) async {
      await montar(tester, 'informe.PDF');

      expect(find.byIcon(Icons.picture_as_pdf), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('una foto de cámara sin extensión se trata como imagen', (tester) async {
      await montar(tester, 'blob');

      expect(find.byType(Image), findsOneWidget);
    });

    test('el tope de tamaño coincide con el del backend (10 MB)', () {
      expect(maxBytesEvidencia, 10 * 1024 * 1024);
    });
  });
}
