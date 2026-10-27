import 'dart:math';

/// Identificador único por envío de formulario. Se reenvía igual en cada reintento
/// (o al sincronizar un registro pendiente) para que el backend no duplique el registro.
String generarClientId() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}
