import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/pallet_tarja_api.dart';
import '../../../core/widgets/evidencia_miniatura.dart';
import '../../control_form/presentation/bobina_qr_scanner_page.dart';
import '../domain/pallet_clasificacion.dart';

const _fondoTarjeta = Color(0xFF1F2A33);
const _fondoItem = Color(0xFF17212B);
const _bordeItem = Color(0xFF37474F);
const _textoSecundario = Color(0xFFB0BEC5);
const _verdeApp = Color(0xFF8BC34A);

Color _colorDe(ColorPallet c) {
  switch (c) {
    case ColorPallet.azul:
      return const Color(0xFF1E88E5);
    case ColorPallet.rojo:
      return const Color(0xFFE53935);
    case ColorPallet.verde:
      return const Color(0xFF43A047);
  }
}

String _miles(num n) {
  final entero = n.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buffer.write('.');
    buffer.write(entero[i]);
  }
  return buffer.toString();
}

/// "2026-11-22T21:08:49" -> "22/11/2026 21:08"
String? _fechaLegible(String? iso) {
  if (iso == null || iso.length < 16) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})').firstMatch(iso);
  if (m == null) return null;
  return '${m[3]}/${m[2]}/${m[1]} ${m[4]}:${m[5]}';
}

typedef FotoSeleccionada = ({Uint8List bytes, String nombre});

/// Sección opcional "Clasificación de pallets" de las inspecciones INNPACK (Calidad y Producción).
/// El operador escanea la tarja (o escribe el código), elige AZUL / ROJO / VERDE y, si quiere, defectos,
/// observación y foto. No bloquea nunca el guardado de la inspección.
class ClasificacionPalletsSection extends StatefulWidget {
  final ClasificacionPalletsController controller;
  final List<Map<String, dynamic>> parametrosVisuales;

  /// Ids de los defectos ya marcados en la inspección (se ofrecen preseleccionados).
  final Set<String> Function()? defectosPreseleccionados;

  // Inyectables para pruebas.
  final PalletTarjaApi? api;
  final Future<String?> Function(BuildContext context)? lector;
  final Future<FotoSeleccionada?> Function()? selectorFoto;

  const ClasificacionPalletsSection({
    super.key,
    required this.controller,
    required this.parametrosVisuales,
    this.defectosPreseleccionados,
    this.api,
    this.lector,
    this.selectorFoto,
  });

  @override
  State<ClasificacionPalletsSection> createState() =>
      _ClasificacionPalletsSectionState();
}

class _ClasificacionPalletsSectionState
    extends State<ClasificacionPalletsSection> {
  late final PalletTarjaApi _api = widget.api ?? PalletTarjaApi();
  bool _consultando = false;

  void _aviso(String texto, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto), action: accion));
  }

  Future<void> _escanear() async {
    final String? codigo = widget.lector != null
        ? await widget.lector!(context)
        : await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => const BobinaQrScannerPage(
                titulo: 'Escanear tarja de pallet',
                instruccion: 'Apunta la cámara a la tarja del pallet',
              ),
            ),
          );
    if (codigo == null || codigo.trim().isEmpty) return;
    await _procesarCodigo(codigo);
  }

  Future<void> _escribirCodigo() async {
    final campo = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código de la tarja'),
        content: TextField(
          controller: campo,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            hintText: 'Ej.: 466568-1',
            helperText: 'El mismo código que trae el QR de la tarja',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, campo.text),
              child: const Text('Buscar')),
        ],
      ),
    );
    if (codigo == null || codigo.trim().isEmpty) return;
    await _procesarCodigo(codigo);
  }

  Future<void> _procesarCodigo(String bruto) async {
    final texto = bruto.trim();
    if (!esCodigoTarjaValido(texto)) {
      _aviso('Este código no corresponde a una tarja de pallet.');
      return;
    }
    if (widget.controller.llegoAlMaximo &&
        widget.controller.indiceDe(texto) < 0) {
      _aviso('Máximo $maxPalletsPorInspeccion pallets por inspección.');
      return;
    }

    setState(() => _consultando = true);
    try {
      var resultado = await _api.consultar(texto);

      if (resultado.tarja == null) {
        // El QR trajo solo el número de registro y hay varias etiquetas: se elige el pallet.
        setState(() => _consultando = false);
        final elegido = await _elegirEtiqueta(resultado.etiquetas);
        if (elegido == null || !mounted) return;
        setState(() => _consultando = true);
        resultado = await _api.consultar(elegido);
      }

      final tarja = resultado.tarja;
      if (tarja != null && mounted) {
        setState(() => _consultando = false);
        await _abrirClasificacion(tarja);
      }
    } on TarjaException catch (e) {
      if (e.permiteSoloCodigo && esCodigoPallet(texto)) {
        _aviso(
          '${e.mensaje} Puede clasificar igual; los datos se completarán al guardar.',
          accion: SnackBarAction(
            label: 'Clasificar',
            onPressed: () => _abrirClasificacion(TarjaPallet.soloCodigo(texto)),
          ),
        );
      } else {
        _aviso(e.mensaje);
      }
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  Future<String?> _elegirEtiqueta(List<EtiquetaRegistro> etiquetas) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Qué pallet?'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in etiquetas)
                ActionChip(
                  label: Text(e.cantidad != null
                      ? 'N° ${e.nEtiqueta} (${_miles(e.cantidad!)} un)'
                      : 'N° ${e.nEtiqueta}'),
                  onPressed: () => Navigator.pop(ctx, e.codigo),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
  }

  Future<void> _abrirClasificacion(TarjaPallet tarja) async {
    final indice = widget.controller.indiceDe(tarja.codigo);
    final existente = indice >= 0 ? widget.controller.items[indice] : null;

    final resultado = await showModalBottomSheet<PalletClasificado>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _fondoTarjeta,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ClasificarPalletSheet(
        tarja: tarja,
        existente: existente,
        parametrosVisuales: widget.parametrosVisuales,
        defectosPreseleccionados:
            (widget.defectosPreseleccionados?.call() ?? <String>{})
                .map(int.tryParse)
                .whereType<int>()
                .toSet(),
        selectorFoto: widget.selectorFoto,
      ),
    );

    if (resultado == null) return;
    widget.controller.guardar(resultado);
    _aviso('Pallet ${resultado.tarja.codigo} clasificado ${resultado.color.valor}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final items = widget.controller.items;
        return Card(
          color: _fondoTarjeta.withOpacity(0.90),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clasificación de pallets',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Opcional. Escanee la tarja de cada pallet que desee clasificar.',
                  style: TextStyle(color: _textoSecundario),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _consultando ? null : _escanear,
                  icon: _consultando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.qr_code_scanner),
                  label: Text(items.isEmpty
                      ? 'Escanear tarja de pallet'
                      : 'Escanear otro pallet'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _verdeApp),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _consultando ? null : _escribirCodigo,
                    child: const Text('Escribir código'),
                  ),
                ),
                if (items.isNotEmpty) ...[
                  Text(
                    widget.controller.resumen,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final p in items)
                    _PalletItem(
                      pallet: p,
                      onEditar: () => _abrirClasificacion(p.tarja),
                      onQuitar: () => widget.controller.quitar(p.tarja.codigo),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PalletItem extends StatelessWidget {
  final PalletClasificado pallet;
  final VoidCallback onEditar;
  final VoidCallback onQuitar;

  const _PalletItem({
    required this.pallet,
    required this.onEditar,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final t = pallet.tarja;
    final detalle = [
      if (t.producto != null) t.producto!,
      if (t.maquina != null) t.maquina!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEditar,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _fondoItem,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _bordeItem),
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _colorDe(pallet.color),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pallet.color.valor,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pallet ${t.codigo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (detalle.isNotEmpty)
                      Text(
                        detalle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _textoSecundario),
                      ),
                    if (pallet.fotoBytes != null)
                      const Text('Con foto',
                          style: TextStyle(color: _textoSecundario)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Quitar',
                onPressed: onQuitar,
                icon: const Icon(Icons.delete_outline, color: _textoSecundario),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClasificarPalletSheet extends StatefulWidget {
  final TarjaPallet tarja;
  final PalletClasificado? existente;
  final List<Map<String, dynamic>> parametrosVisuales;
  final Set<int> defectosPreseleccionados;
  final Future<FotoSeleccionada?> Function()? selectorFoto;

  const _ClasificarPalletSheet({
    required this.tarja,
    required this.existente,
    required this.parametrosVisuales,
    required this.defectosPreseleccionados,
    required this.selectorFoto,
  });

  @override
  State<_ClasificarPalletSheet> createState() => _ClasificarPalletSheetState();
}

class _ClasificarPalletSheetState extends State<_ClasificarPalletSheet> {
  ColorPallet? _color;
  late final Set<int> _defectos;
  late final TextEditingController _observacion;
  Uint8List? _fotoBytes;
  String? _fotoNombre;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _color = e?.color;
    _defectos = {...(e?.defectoIds ?? widget.defectosPreseleccionados)};
    _observacion = TextEditingController(text: e?.observacion ?? '');
    _fotoBytes = e?.fotoBytes;
    _fotoNombre = e?.fotoNombre;
  }

  @override
  void dispose() {
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _agregarFoto() async {
    FotoSeleccionada? foto;
    if (widget.selectorFoto != null) {
      foto = await widget.selectorFoto!();
    } else {
      final XFile? x = await ImagePicker().pickImage(source: ImageSource.camera);
      if (x != null) foto = (bytes: await x.readAsBytes(), nombre: x.name);
    }
    if (foto == null) return;
    if (foto.bytes.length > maxBytesEvidencia) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La foto supera el máximo de 25 MB')),
      );
      return;
    }
    setState(() {
      _fotoBytes = foto!.bytes;
      _fotoNombre = foto.nombre;
    });
  }

  void _guardar() {
    final color = _color;
    if (color == null) return;
    Navigator.pop(
      context,
      PalletClasificado(
        tarja: widget.tarja,
        color: color,
        // Los defectos solo aplican a AZUL / ROJO.
        defectoIds: color == ColorPallet.verde ? <int>{} : {..._defectos},
        observacion: _observacion.text.trim(),
        fotoBytes: _fotoBytes,
        fotoNombre: _fotoNombre,
      ),
    );
  }

  Widget _dato(String etiqueta, String? valor) {
    if (valor == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$etiqueta: ', style: const TextStyle(color: _textoSecundario)),
          TextSpan(text: valor, style: const TextStyle(color: Colors.white)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tarja;
    final estado = t.estadoActual;
    final fecha = _fechaLegible(t.fechaTarja);
    final np = [
      if (t.npFaret != null) t.npFaret!,
      if (t.npInnpack != null) t.npInnpack!,
    ].join(' / ');
    final mostrarDefectos = _color == ColorPallet.azul || _color == ColorPallet.rojo;

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pallet ${t.codigo}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              if (!t.conDatos)
                const Text(
                  'Sin datos de producción por ahora. Se completarán al guardar.',
                  style: TextStyle(color: Color(0xFFFFCC80)),
                )
              else ...[
                _dato('Cliente', t.cliente),
                _dato('Producto', t.producto),
                _dato('NP', np.isEmpty ? null : np),
                _dato('Orden', t.ordenFabricacion),
                _dato('Máquina', t.maquina),
                _dato('Operador', t.operador),
                _dato('Cantidad',
                    t.cantidad != null ? '${_miles(t.cantidad!)} un' : null),
                _dato('Tarja', fecha),
              ],
              if (estado?.color != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _fondoItem,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _colorDe(estado!.color!)),
                  ),
                  child: Text(
                    'Actualmente ${estado.color!.valor}'
                    '${_fechaLegible(estado.clasificadoEn) != null ? ' desde ${_fechaLegible(estado.clasificadoEn)}' : ''}. '
                    'Se registrará como una nueva clasificación.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final c in ColorPallet.values) ...[
                    Expanded(
                      child: _BotonColor(
                        color: c,
                        seleccionado: _color == c,
                        onTap: () => setState(() => _color = c),
                      ),
                    ),
                    if (c != ColorPallet.verde) const SizedBox(width: 10),
                  ],
                ],
              ),
              if (mostrarDefectos && widget.parametrosVisuales.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Defectos (opcional)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in widget.parametrosVisuales)
                      if (int.tryParse(p['id'].toString()) != null)
                        FilterChip(
                          label: Text(p['nombre'].toString()),
                          selected:
                              _defectos.contains(int.parse(p['id'].toString())),
                          onSelected: (v) => setState(() {
                            final id = int.parse(p['id'].toString());
                            v ? _defectos.add(id) : _defectos.remove(id);
                          }),
                        ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _observacion,
                maxLength: 500,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Observación (opcional)',
                  labelStyle: TextStyle(color: _textoSecundario),
                  border: OutlineInputBorder(),
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _agregarFoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(_fotoBytes == null ? 'Agregar foto' : 'Cambiar foto'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: _bordeItem),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_fotoBytes != null) ...[
                    EvidenciaMiniatura(
                        bytes: _fotoBytes!, nombre: _fotoNombre ?? 'foto.jpg'),
                    IconButton(
                      tooltip: 'Quitar foto',
                      onPressed: () => setState(() {
                        _fotoBytes = null;
                        _fotoNombre = null;
                      }),
                      icon: const Icon(Icons.close, color: _textoSecundario),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: _color == null ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _verdeApp,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF37474F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _color == null ? 'ELIJA AZUL, ROJO O VERDE' : 'GUARDAR CLASIFICACIÓN',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonColor extends StatelessWidget {
  final ColorPallet color;
  final bool seleccionado;
  final VoidCallback onTap;

  const _BotonColor({
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: seleccionado,
      label: color.valor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: _colorDe(color),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: seleccionado ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (seleccionado)
                const Icon(Icons.check_circle, color: Colors.white, size: 22),
              Text(
                color.valor,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
