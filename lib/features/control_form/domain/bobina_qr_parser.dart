/// Port fiel del parser de QR de tarjas de bobina de papel usado en
/// `consumo_papel/helpers/qr_parser.php` + `public/qr_scan.js`. El QR físico
/// de la tarja NO trae tipo de papel/gramaje/medida como campos separados —
/// solo codifica lote (ID único de la bobina) + peso + docnum opcional. El
/// resto de los datos se resuelve después contra SAP por el lote.
library;

class BobinaQrParseResult {
  final String? lote;
  final String? docnum;
  final double? tarjaKg;

  const BobinaQrParseResult({this.lote, this.docnum, this.tarjaKg});
}

String _qrNormalize(String raw) {
  var s = raw.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('\t', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s.trim();
}

/// Detecta lotes aunque tengan basura o ceros de relleno:
/// 000103551-20 -> 3551-20, 000010108-04 -> 108-04, 00001095-09 -> 95-09.
String? detectarLoteInteligente(String s) {
  final m = RegExp(r'0+1?0*(\d{2,6})-(\d{1,4})').firstMatch(s);
  if (m == null) return null;

  var num = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
  final suf = m.group(2)!;

  if (num.isEmpty) {
    num = m.group(1)!;
  }

  final mm = RegExp(r'^10(\d{2,})$').firstMatch(num);
  if (mm != null) {
    num = mm.group(1)!;
  }

  return '$num-$suf';
}

/// Detecta el peso exacto codificado en el QR. Toma la ÚLTIMA ocurrencia de
/// "37" (marcador GS1 de peso neto) antes del lote, NO la primera — un
/// código de artículo que contenga otro "37" antes calcularía un peso
/// disparatado si se tomara el primero (bug ya corregido en el sistema
/// original, ver `consumo_papel/CLAUDE.md`).
double? detectarPesoInteligente(String raw) {
  final s = _qrNormalize(raw);

  if (s.isEmpty) return null;

  final loteMatch = RegExp(r'0+1?0*\d{2,6}-\d{1,4}(?=#|$)').firstMatch(s);
  if (loteMatch == null) return null;

  final posLote = loteMatch.start;
  final antesDelLote =
      s.substring(0, posLote).replaceAll(RegExp(r'\s+'), '');

  if (antesDelLote.isEmpty) return null;

  final posUltimo37 = antesDelLote.lastIndexOf('37');
  if (posUltimo37 == -1) return null;

  final rawPeso = antesDelLote.substring(posUltimo37 + 2);
  if (rawPeso.isEmpty) return null;

  // Caso A: viene con coma como separador antes del lote (371188, / 37850,).
  if (rawPeso.contains(',')) {
    final parteEntera = rawPeso.split(',').first;
    var digits = parteEntera.replaceAll(RegExp(r'\D+'), '');

    if (digits.isEmpty) return null;

    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.isEmpty) return 0.0;

    return double.parse(digits);
  }

  // Caso B: sin coma, con 2 decimales implícitos (00002000 -> 20).
  final digits = rawPeso.replaceAll(RegExp(r'\D+'), '');
  if (digits.isEmpty) return null;

  return double.parse(digits) / 100;
}

/// QR de excepción: trae un sufijo extra con "|" (ej. `...#911000037|3110...`).
/// En esos casos el peso leído del QR no es confiable y se descarta.
bool esQrExcepcion(String raw) {
  final s = raw.replaceAll(RegExp(r'\s+'), '');
  return s.contains('|');
}

BobinaQrParseResult parseBobinaQr(String raw) {
  final s = _qrNormalize(raw);

  if (s.isEmpty) {
    return const BobinaQrParseResult();
  }

  // Excepción manual: el QR normaliza doble espacio a uno, pero SAP debe
  // buscarlo con doble espacio.
  if (s == 'AJUSTE MAYO 2026') {
    return const BobinaQrParseResult(lote: 'AJUSTE  MAYO 2026');
  }

  String? lote = detectarLoteInteligente(s);

  if (lote == null) {
    // Motor clásico de lote (fallback).
    final m =
        RegExp(r'(?:^|[^\d])0*(\d{3,6}-\d{1,4})(?:[^\d]|$)').firstMatch(s);

    if (m != null) {
      final loteRaw = m.group(1)!.replaceFirst(RegExp(r'^0+'), '');
      final parts = loteRaw.split('-');
      var num = parts.first;
      final suf = parts.sublist(1).join('-');

      final mm = RegExp(r'^10(\d{2,})$').firstMatch(num);
      if (mm != null) {
        num = mm.group(1)!;
      }

      lote = '$num-$suf';
    }
  }

  if (lote == null) {
    // Lote directo desde código de barra 1D (sin guión, sin envoltorio GS1).
    // Ej: T010128343, 30206935011319. Solo si no hay marcadores típicos de
    // QR de tarja (# de docnum, , de peso), para no inventar un lote.
    if (!s.contains('#') &&
        !s.contains(',') &&
        RegExp(r'^[A-Z0-9]{4,30}$', caseSensitive: false).hasMatch(s)) {
      lote = s;
    }
  }

  String? docnum;
  final docMatch = RegExp(r'#(\d{6,})').firstMatch(s);
  if (docMatch != null) {
    docnum = docMatch.group(1);
  }

  final tarjaKg = esQrExcepcion(raw) ? null : detectarPesoInteligente(s);

  return BobinaQrParseResult(lote: lote, docnum: docnum, tarjaKg: tarjaKg);
}
