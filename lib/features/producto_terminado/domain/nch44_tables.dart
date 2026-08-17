/// Datos de NCh44:2007 — Tabla 1 (letras código) y Tabla 2-A (planes de
/// muestreo simple, inspección normal). Parametrización exacta de las
/// tablas suministradas; no se aproxima ni se recalcula estadísticamente.
class RangoLote {
  final int loteMin;
  final int? loteMax;
  final String nivelI;
  final String nivelII;
  final String nivelIII;

  const RangoLote({
    required this.loteMin,
    required this.loteMax,
    required this.nivelI,
    required this.nivelII,
    required this.nivelIII,
  });
}

/// Tabla 1 - Letras código del tamaño de muestra, niveles generales I/II/III.
const List<RangoLote> tabla1Rangos = [
  RangoLote(loteMin: 2, loteMax: 8, nivelI: 'A', nivelII: 'A', nivelIII: 'B'),
  RangoLote(loteMin: 9, loteMax: 15, nivelI: 'A', nivelII: 'B', nivelIII: 'C'),
  RangoLote(loteMin: 16, loteMax: 25, nivelI: 'B', nivelII: 'C', nivelIII: 'D'),
  RangoLote(loteMin: 26, loteMax: 50, nivelI: 'C', nivelII: 'D', nivelIII: 'E'),
  RangoLote(loteMin: 51, loteMax: 90, nivelI: 'C', nivelII: 'E', nivelIII: 'F'),
  RangoLote(loteMin: 91, loteMax: 150, nivelI: 'D', nivelII: 'F', nivelIII: 'G'),
  RangoLote(loteMin: 151, loteMax: 280, nivelI: 'E', nivelII: 'G', nivelIII: 'H'),
  RangoLote(loteMin: 281, loteMax: 500, nivelI: 'F', nivelII: 'H', nivelIII: 'J'),
  RangoLote(loteMin: 501, loteMax: 1200, nivelI: 'G', nivelII: 'J', nivelIII: 'K'),
  RangoLote(loteMin: 1201, loteMax: 3200, nivelI: 'H', nivelII: 'K', nivelIII: 'L'),
  RangoLote(loteMin: 3201, loteMax: 10000, nivelI: 'J', nivelII: 'L', nivelIII: 'M'),
  RangoLote(loteMin: 10001, loteMax: 35000, nivelI: 'K', nivelII: 'M', nivelIII: 'N'),
  RangoLote(loteMin: 35001, loteMax: 150000, nivelI: 'L', nivelII: 'N', nivelIII: 'P'),
  RangoLote(loteMin: 150001, loteMax: 500000, nivelI: 'M', nivelII: 'P', nivelIII: 'Q'),
  RangoLote(loteMin: 500001, loteMax: null, nivelI: 'N', nivelII: 'Q', nivelIII: 'R'),
];

/// Letras código en orden creciente de tamaño de muestra (Tabla 2-A).
const List<String> letrasOrden = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R',
];

const Map<String, int> tamanoMuestraPorLetra = {
  'A': 2,
  'B': 3,
  'C': 5,
  'D': 8,
  'E': 13,
  'F': 20,
  'G': 32,
  'H': 50,
  'J': 80,
  'K': 125,
  'L': 200,
  'M': 315,
  'N': 500,
  'P': 800,
  'Q': 1250,
  'R': 2000,
};

/// AQL disponibles en la Tabla 2-A (columnas, en orden).
const List<double> aqlValues = [
  0.010, 0.015, 0.025, 0.040, 0.065, 0.10, 0.15, 0.25, 0.40, 0.65,
  1.0, 1.5, 2.5, 4.0, 6.5, 10, 15, 25, 40, 65,
  100, 150, 250, 400, 650, 1000,
];

/// Pares (Ac, Re) usados en la Tabla 2-A, en orden creciente de severidad.
const List<List<int>> paresAcRe = [
  [0, 1],
  [1, 2],
  [2, 3],
  [3, 4],
  [5, 6],
  [7, 8],
  [10, 11],
  [14, 15],
  [21, 22],
  [30, 31],
  [44, 45],
];
