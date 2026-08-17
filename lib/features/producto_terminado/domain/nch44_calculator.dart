import 'nch44_tables.dart';

/// Resultado de aplicar NCh44:2007 (Tabla 1 + Tabla 2-A) a un lote/nivel/AQL.
class PlanMuestreo {
  final String letraCodigo;
  final int tamanoMuestra;
  final int? ac;
  final int? re;
  final bool inspeccion100;
  final String? notaFlecha;

  const PlanMuestreo({
    required this.letraCodigo,
    required this.tamanoMuestra,
    required this.ac,
    required this.re,
    required this.inspeccion100,
    this.notaFlecha,
  });
}

/// Determina la letra código de Tabla 1 para un lote/nivel, sin aplicar
/// todavía las reglas de flecha de Tabla 2-A. Expuesta (no privada) para
/// poder testear Tabla 1 de forma aislada de Tabla 2-A.
String letraTabla1(int cantidadLote, String nivel) {
  for (final rango in tabla1Rangos) {
    final dentroMin = cantidadLote >= rango.loteMin;
    final dentroMax = rango.loteMax == null || cantidadLote <= rango.loteMax!;

    if (dentroMin && dentroMax) {
      switch (nivel) {
        case 'I':
          return rango.nivelI;
        case 'II':
          return rango.nivelII;
        case 'III':
          return rango.nivelIII;
        default:
          throw ArgumentError('Nivel de inspección inválido: $nivel');
      }
    }
  }

  throw ArgumentError('Cantidad de lote fuera de rango de Tabla 1: $cantidadLote');
}

/// Calcula el plan de muestreo NCh44:2007 (inspección normal, muestreo
/// simple) para un lote de [cantidadLote] unidades, [nivel] general de
/// inspección ('I'/'II'/'III') y [aql] (debe ser uno de los valores exactos
/// de Tabla 2-A). Aplica las reglas de flecha (↓ usar plan de letra mayor,
/// ↑ usar plan de letra menor) y la regla de inspección 100% cuando el
/// tamaño de muestra iguala o excede al tamaño del lote.
PlanMuestreo calcularPlanMuestreo(int cantidadLote, String nivel, double aql) {
  final letra = letraTabla1(cantidadLote, nivel);
  final filaIndex = letrasOrden.indexOf(letra);
  final colIndex = aqlValues.indexWhere((v) => (v - aql).abs() < 0.0001);

  if (colIndex == -1) {
    throw ArgumentError('AQL no está en la Tabla 2-A suministrada: $aql');
  }

  final tamanoOriginal = tamanoMuestraPorLetra[letra]!;

  if (tamanoOriginal >= cantidadLote) {
    return PlanMuestreo(
      letraCodigo: letra,
      tamanoMuestra: cantidadLote,
      ac: null,
      re: null,
      inspeccion100: true,
      notaFlecha:
          'Tamaño de muestra de letra $letra ($tamanoOriginal) >= tamaño de lote: inspección 100%',
    );
  }

  final idx = colIndex + filaIndex - 16;

  if (idx >= 0 && idx <= 10) {
    final par = paresAcRe[idx];

    return PlanMuestreo(
      letraCodigo: letra,
      tamanoMuestra: tamanoOriginal,
      ac: par[0],
      re: par[1],
      inspeccion100: false,
    );
  }

  if (idx < 0) {
    final targetIndex = 16 - colIndex;

    if (targetIndex > 15) {
      return PlanMuestreo(
        letraCodigo: letra,
        tamanoMuestra: tamanoOriginal,
        ac: null,
        re: null,
        inspeccion100: true,
        notaFlecha:
            'No existe plan de muestreo válido para este AQL en Tabla 2-A: inspección 100%',
      );
    }

    final letraDestino = letrasOrden[targetIndex];
    final tamanoDestino = tamanoMuestraPorLetra[letraDestino]!;

    if (tamanoDestino >= cantidadLote) {
      return PlanMuestreo(
        letraCodigo: letraDestino,
        tamanoMuestra: cantidadLote,
        ac: null,
        re: null,
        inspeccion100: true,
        notaFlecha:
            'Regla de flecha ↓ desde letra $letra: tamaño de muestra >= lote, inspección 100%',
      );
    }

    return PlanMuestreo(
      letraCodigo: letraDestino,
      tamanoMuestra: tamanoDestino,
      ac: paresAcRe[0][0],
      re: paresAcRe[0][1],
      inspeccion100: false,
      notaFlecha:
          'Regla de flecha ↓: se usó el plan de letra $letraDestino (muestra $tamanoDestino) en vez de $letra',
    );
  }

  // idx > 10: regla de flecha hacia arriba (↑).
  final targetIndex = 26 - colIndex;
  final letraDestino = letrasOrden[targetIndex];
  final tamanoDestino = tamanoMuestraPorLetra[letraDestino]!;

  return PlanMuestreo(
    letraCodigo: letraDestino,
    tamanoMuestra: tamanoDestino,
    ac: paresAcRe[10][0],
    re: paresAcRe[10][1],
    inspeccion100: false,
    notaFlecha:
        'Regla de flecha ↑: se usó el plan de letra $letraDestino (muestra $tamanoDestino) en vez de $letra',
  );
}
