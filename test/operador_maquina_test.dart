import 'package:flutter_test/flutter_test.dart';
import 'package:quality_control/core/local/pending_records_store.dart';
import 'package:quality_control/features/control_form/domain/control_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ControlContext contexto({List<Map<String, dynamic>>? operadores}) {
    return ControlContext(
      machineId: 6,
      machineName: 'Troquelado 104-1',
      processId: 3,
      processName: 'Troquelado',
      formId: null,
      formName: '',
      userId: 1,
      userName: 'Inspector',
      operatorArea: 'CALIDAD INNPACK',
      parametrosVisuales: const [],
      operadoresMaquina: operadores ?? const [],
    );
  }

  group('operador de máquina', () {
    test('catálogo antiguo sin operadoresMaquina: contexto vacío (no aparece el selector)', () {
      expect(contexto().operadoresMaquina, isEmpty);
    });

    test('contexto con operadores los conserva tal como llegan del catálogo', () {
      final c = contexto(operadores: [
        {'id': 1, 'proceso_id': 3, 'nombre': 'Kervin Mosquera'},
      ]);
      expect(c.operadoresMaquina.single['nombre'], 'Kervin Mosquera');
    });

    test('registro offline guarda operadorMaquinaId y lo entrega intacto al sincronizar', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingRecordsStore();

      await store.savePendingRecord({
        'usuarioId': 1,
        'procesoId': 3,
        'maquinaId': 6,
        'operadorMaquinaId': 1,
      });

      final pendientes = await store.getPendingRecords();
      expect(pendientes, hasLength(1));
      expect(pendientes.single['payload']['operadorMaquinaId'], 1);
    });

    test('registro offline sin operador (opcional) se guarda con operadorMaquinaId nulo', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingRecordsStore();

      await store.savePendingRecord({
        'usuarioId': 1,
        'procesoId': 3,
        'maquinaId': 6,
        'operadorMaquinaId': null,
      });

      final pendientes = await store.getPendingRecords();
      expect(pendientes.single['payload']['operadorMaquinaId'], isNull);
    });

    test('registro pendiente creado por un APK anterior (sin el campo) sigue siendo legible', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingRecordsStore();

      await store.savePendingRecord({'usuarioId': 1, 'procesoId': 3, 'maquinaId': 6});

      final payload = (await store.getPendingRecords()).single['payload'] as Map;
      expect(payload.containsKey('operadorMaquinaId'), isFalse);
    });
  });
}
