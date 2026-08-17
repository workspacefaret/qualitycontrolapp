/// Calcula el turno (A/B/C) según la hora en que se realiza el registro.
///
/// Turno A: 07:00 - 14:29
/// Turno B: 14:30 - 23:29
/// Turno C: 23:30 - 06:59
String calcularTurno(DateTime momento) {
  final minutosDelDia = momento.hour * 60 + momento.minute;

  const inicioA = 7 * 60;
  const inicioB = 14 * 60 + 30;
  const inicioC = 23 * 60 + 30;

  if (minutosDelDia >= inicioA && minutosDelDia < inicioB) {
    return 'A';
  }
  if (minutosDelDia >= inicioB && minutosDelDia < inicioC) {
    return 'B';
  }
  return 'C';
}
