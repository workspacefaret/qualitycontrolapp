import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/catalogos_api.dart';
import '../../../core/api/orden_fabricacion_api.dart';
import '../../../core/api/producto_terminado_api.dart';
import '../../../core/utils/turno_calculator.dart';
import '../domain/nch44_calculator.dart';
import '../domain/nch44_tables.dart';

class _Hallazgo {
  final Set<int> defectoIds = {};
  int? origenId;
  final TextEditingController observacionController = TextEditingController();
  Uint8List? fotoBytes;
  String? fotoNombre;

  void dispose() {
    observacionController.dispose();
  }
}

class ProductoTerminadoFormPage extends StatefulWidget {
  final int usuarioId;
  final String usuarioNombre;

  const ProductoTerminadoFormPage({
    super.key,
    required this.usuarioId,
    required this.usuarioNombre,
  });

  @override
  State<ProductoTerminadoFormPage> createState() =>
      _ProductoTerminadoFormPageState();
}

class _ProductoTerminadoFormPageState
    extends State<ProductoTerminadoFormPage> {
  final CatalogosApi _catalogosApi = CatalogosApi();
  final OrdenFabricacionApi _ordenFabricacionApi = OrdenFabricacionApi();
  final ProductoTerminadoApi _productoTerminadoApi = ProductoTerminadoApi();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _npController = TextEditingController();
  final TextEditingController _cantidadLoteController =
      TextEditingController();
  final TextEditingController _cantidadPalletsController =
      TextEditingController();
  final TextEditingController _cantidadCajasBinsController =
      TextEditingController();
  final TextEditingController _palletIdController = TextEditingController();
  final TextEditingController _maquinaController = TextEditingController();

  String? _procesoPt;
  String? _empresa;
  String? _cliente;
  String? _productCode;
  String? _productDescription;
  bool _buscandoOrden = false;
  List<Map<String, dynamic>> _ordenItems = [];
  String? _selectedOrdenItem;

  List<Map<String, dynamic>> _parametrosVisuales = [];
  List<Map<String, dynamic>> _origenesProblema = [];
  bool _cargandoCatalogoProceso = false;

  String? _nivelInspeccion;
  double? _aql;
  PlanMuestreo? _plan;
  String? _errorPlan;

  final List<_Hallazgo> _hallazgos = [];
  bool _guardando = false;

  @override
  void dispose() {
    _npController.dispose();
    _cantidadLoteController.dispose();
    _cantidadPalletsController.dispose();
    _cantidadCajasBinsController.dispose();
    _palletIdController.dispose();
    _maquinaController.dispose();
    for (final h in _hallazgos) {
      h.dispose();
    }
    super.dispose();
  }

  Future<void> _onProcesoPtChanged(String? value) async {
    setState(() {
      _procesoPt = value;
      _maquinaController.clear();
      _parametrosVisuales = [];
      _origenesProblema = [];
      _cargandoCatalogoProceso = true;
      for (final h in _hallazgos) {
        h.dispose();
      }
      _hallazgos.clear();
    });

    if (value == null) {
      setState(() => _cargandoCatalogoProceso = false);
      return;
    }

    final procesoId = value == 'Termoformado' ? 5 : 4;

    try {
      final parametros =
          await _catalogosApi.obtenerParametrosVisuales(procesoId);
      final origenes = await _catalogosApi.obtenerOrigenesProblema(procesoId);

      if (!mounted) return;

      setState(() {
        _parametrosVisuales = parametros;
        _origenesProblema = origenes;
        _cargandoCatalogoProceso = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _cargandoCatalogoProceso = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar el catálogo de defectos/origen'),
        ),
      );
    }
  }

  Future<void> _buscarItemsPorNp() async {
    final np = _npController.text.trim();

    if (np.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese el NP antes de buscar')),
      );
      return;
    }

    setState(() => _buscandoOrden = true);

    try {
      final data = await _ordenFabricacionApi.obtenerOrdenFabricacion(
        np,
        proceso: _procesoPt,
      );

      if (!mounted) return;

      final items = List<Map<String, dynamic>>.from(
        (data['items'] as List?) ?? [],
      );

      setState(() {
        _cliente = data['cliente']?.toString();
        _ordenItems = items;

        if (items.length == 1) {
          _selectedOrdenItem = items.first['codigo']?.toString();
          _productCode = items.first['codigo']?.toString();
          _productDescription = items.first['nombre']?.toString();
        } else {
          _selectedOrdenItem = null;
          _productCode = null;
          _productDescription = null;
        }
      });

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontraron ítems para este NP')),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No se pudo consultar el NP. Puede continuar manualmente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _buscandoOrden = false);
    }
  }

  void _agregarPallet() {
    final value = _palletIdController.text.trim();

    if (value.isEmpty) return;

    setState(() {
      _palletIdController.clear();
    });

    _palletsIds.add(value);
    setState(() {});
  }

  final List<String> _palletsIds = [];

  void _quitarPallet(int index) {
    setState(() {
      _palletsIds.removeAt(index);
    });
  }

  void _recalcularPlan() {
    final cantidadLote = int.tryParse(_cantidadLoteController.text.trim());

    if (cantidadLote == null || _nivelInspeccion == null || _aql == null) {
      setState(() {
        _plan = null;
        _errorPlan = null;
      });
      return;
    }

    try {
      final plan = calcularPlanMuestreo(cantidadLote, _nivelInspeccion!, _aql!);

      setState(() {
        _plan = plan;
        _errorPlan = null;
      });
    } catch (error) {
      setState(() {
        _plan = null;
        _errorPlan = error.toString();
      });
    }
  }

  void _agregarHallazgo() {
    setState(() {
      _hallazgos.add(_Hallazgo());
    });
  }

  void _quitarHallazgo(int index) {
    setState(() {
      _hallazgos[index].dispose();
      _hallazgos.removeAt(index);
    });
  }

  Future<void> _tomarFotoHallazgo(_Hallazgo hallazgo) async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );

    if (photo == null) return;

    final bytes = await photo.readAsBytes();

    setState(() {
      hallazgo.fotoBytes = bytes;
      hallazgo.fotoNombre = photo.name;
    });
  }

  Future<void> _seleccionarArchivoHallazgo(_Hallazgo hallazgo) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    setState(() {
      hallazgo.fotoBytes = result.files.single.bytes;
      hallazgo.fotoNombre = result.files.single.name;
    });
  }

  int get _defectosTotales =>
      _hallazgos.fold(0, (total, h) => total + h.defectoIds.length);

  bool _hallazgoTieneOtro(_Hallazgo hallazgo) {
    return hallazgo.defectoIds.any((id) {
      final parametro = _parametrosVisuales.firstWhere(
        (p) => p['id'] == id,
        orElse: () => const {},
      );
      return parametro['nombre']?.toString().startsWith('Otro') ?? false;
    });
  }

  String? _validarHallazgos() {
    if (_hallazgos.isEmpty) {
      return null;
    }

    for (var i = 0; i < _hallazgos.length; i++) {
      final h = _hallazgos[i];
      final n = i + 1;

      if (h.defectoIds.isEmpty) {
        return 'Hallazgo $n: seleccione al menos un defecto';
      }

      if (h.defectoIds.length > 3) {
        return 'Hallazgo $n: máximo 3 defectos';
      }

      if (h.origenId == null) {
        return 'Hallazgo $n: seleccione el origen';
      }

      if (h.fotoBytes == null) {
        return 'Hallazgo $n: falta la foto (obligatoria)';
      }

      if (_hallazgoTieneOtro(h) && h.observacionController.text.trim().isEmpty) {
        return 'Hallazgo $n: observación obligatoria al seleccionar "Otro"';
      }
    }

    return null;
  }

  String _calcularResultado() {
    final unidadesNc = _hallazgos.length;

    if (_plan == null || _plan!.inspeccion100) {
      return unidadesNc > 0 ? 'NO CONFORME' : 'CONFORME';
    }

    if (unidadesNc <= _plan!.ac!) {
      return 'CONFORME';
    }

    return 'NO CONFORME';
  }

  Future<void> _finalizarInspeccion() async {
    if (_npController.text.trim().isEmpty) {
      _mostrarError('Debe ingresar NP');
      return;
    }

    if (_procesoPt == null) {
      _mostrarError('Debe seleccionar el proceso PT (Termoformado/Pegado)');
      return;
    }

    if (_empresa == null) {
      _mostrarError('Debe seleccionar la Empresa (Faret/Innpack)');
      return;
    }

    if (_ordenItems.isNotEmpty && _productCode == null) {
      _mostrarError('Debe seleccionar el ítem del NP');
      return;
    }

    final cantidadLote = int.tryParse(_cantidadLoteController.text.trim());

    if (cantidadLote == null || cantidadLote < 2) {
      _mostrarError('Cantidad de lote inválida');
      return;
    }

    if (_plan == null) {
      _mostrarError(_errorPlan ?? 'Debe seleccionar nivel de inspección y AQL');
      return;
    }

    final errorHallazgos = _validarHallazgos();
    if (errorHallazgos != null) {
      _mostrarError(errorHallazgos);
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar finalización'),
        content: Text(
          '¿Confirma que se revisó físicamente la totalidad de la muestra '
          'requerida (${_plan!.tamanoMuestra} unidades)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    final resultado = _calcularResultado();

    setState(() => _guardando = true);

    final payload = {
      'usuarioId': widget.usuarioId,
      'np': _npController.text.trim(),
      'cliente': _cliente,
      'codigoProducto': _productCode,
      'descripcionProducto': _productDescription,
      'procesoPt': _procesoPt,
      'empresa': _empresa,
      'cantidadLote': cantidadLote,
      'cantidadPallets': int.tryParse(_cantidadPalletsController.text.trim()),
      'cantidadCajasBins': _procesoPt == 'Termoformado'
          ? int.tryParse(_cantidadCajasBinsController.text.trim())
          : null,
      'maquina': _maquinaController.text.trim().isEmpty
          ? null
          : _maquinaController.text.trim(),
      'turno': calcularTurno(DateTime.now()),
      'nivelInspeccion': _nivelInspeccion,
      'aql': _aql,
      'letraCodigo': _plan!.letraCodigo,
      'tamanoMuestra': _plan!.tamanoMuestra,
      'ac': _plan!.ac,
      're': _plan!.re,
      'inspeccion100': _plan!.inspeccion100,
      'resultado': resultado,
      'pallets': _palletsIds,
      'hallazgos': _hallazgos
          .map(
            (h) => {
              'defectoIds': h.defectoIds.toList(),
              'origenId': h.origenId,
              'observacion': h.observacionController.text.trim(),
            },
          )
          .toList(),
    };

    final fotosBytes = _hallazgos.map((h) => h.fotoBytes!).toList();
    final fotosNombres = _hallazgos
        .map((h) => h.fotoNombre ?? 'hallazgo.jpg')
        .toList();

    try {
      await _productoTerminadoApi.guardarRegistro(
        payload,
        fotosBytes: fotosBytes,
        fotosNombres: fotosNombres,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inspección guardada correctamente: $resultado')),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $error')),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final currentShift = calcularTurno(now);

    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2A33),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Producto Terminado'),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.74),
                Colors.black.withOpacity(0.62),
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información del lote',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _InfoLine('Fecha: $currentDate'),
                            _InfoLine('Hora: $currentTime'),
                            _InfoLine('Inspector: ${widget.usuarioNombre}'),
                            _InfoLine('Turno: $currentShift'),
                            const SizedBox(height: 12),
                            _DarkTextField(
                              controller: _npController,
                              label: 'NP',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _buscandoOrden ? null : _buscarItemsPorNp,
                              icon: _buscandoOrden
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.search),
                              label: const Text('Buscar ítems del NP'),
                              style: _outlinedStyle,
                            ),
                            if (_cliente != null) ...[
                              const SizedBox(height: 10),
                              _InfoLine('Cliente: $_cliente', bold: true),
                            ],
                            if (_ordenItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _DarkDropdown<String>(
                                label: 'Ítem del NP',
                                value: _selectedOrdenItem,
                                items: _ordenItems
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item['codigo'].toString(),
                                        child: Text(
                                          '${item['codigo']} - ${item['nombre'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  final item = _ordenItems.firstWhere(
                                    (e) => e['codigo'].toString() == value,
                                  );
                                  setState(() {
                                    _selectedOrdenItem = value;
                                    _productCode = item['codigo']?.toString();
                                    _productDescription =
                                        item['nombre']?.toString();
                                  });
                                },
                              ),
                            ],
                            if (_productCode != null) ...[
                              const SizedBox(height: 10),
                              _InfoLine('Código: $_productCode', bold: true),
                              if (_productDescription != null)
                                _InfoLine('Producto: $_productDescription'),
                            ],
                            const SizedBox(height: 12),
                            _DarkDropdown<String>(
                              label: 'Proceso PT',
                              value: _procesoPt,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Termoformado',
                                  child: Text('Termoformado'),
                                ),
                                DropdownMenuItem(
                                  value: 'Pegado',
                                  child: Text('Pegado'),
                                ),
                              ],
                              onChanged: _onProcesoPtChanged,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Empresa',
                              style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: ['FARET', 'INNPACK'].map((empresa) {
                                final selected = _empresa == empresa;
                                return ChoiceChip(
                                  label: Text(
                                    empresa == 'FARET' ? 'Faret' : 'Innpack',
                                  ),
                                  selected: selected,
                                  onSelected: (_) =>
                                      setState(() => _empresa = empresa),
                                  selectedColor: const Color(0xFF8BC34A),
                                  backgroundColor: const Color(0xFFEEF3F5),
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF263238),
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                            _DarkTextField(
                              controller: _maquinaController,
                              label: 'Máquina',
                            ),
                            const SizedBox(height: 12),
                            _DarkTextField(
                              controller: _cantidadLoteController,
                              label: 'Cantidad lote',
                              keyboardType: TextInputType.number,
                              onChanged: (_) => _recalcularPlan(),
                            ),
                            const SizedBox(height: 12),
                            _DarkTextField(
                              controller: _cantidadPalletsController,
                              label: 'Cantidad pallets',
                              keyboardType: TextInputType.number,
                            ),
                            if (_procesoPt == 'Termoformado') ...[
                              const SizedBox(height: 12),
                              _DarkTextField(
                                controller: _cantidadCajasBinsController,
                                label: 'Cantidad cajas/bins',
                                keyboardType: TextInputType.number,
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Text(
                              'ID pallet(s)',
                              style: TextStyle(color: Color(0xFFB0BEC5)),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _DarkTextField(
                                    controller: _palletIdController,
                                    label: 'ID pallet',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _agregarPallet,
                                  icon: const Icon(Icons.add_circle,
                                      color: Color(0xFF8BC34A)),
                                ),
                              ],
                            ),
                            for (var i = 0; i < _palletsIds.length; i++)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  _palletsIds[i],
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Color(0xFFFFCC80)),
                                  onPressed: () => _quitarPallet(i),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Muestreo NCh44:2007',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _DarkDropdown<String>(
                              label: 'Nivel general de inspección',
                              value: _nivelInspeccion,
                              items: const [
                                DropdownMenuItem(value: 'I', child: Text('I')),
                                DropdownMenuItem(
                                    value: 'II', child: Text('II')),
                                DropdownMenuItem(
                                    value: 'III', child: Text('III')),
                              ],
                              onChanged: (value) {
                                setState(() => _nivelInspeccion = value);
                                _recalcularPlan();
                              },
                            ),
                            const SizedBox(height: 12),
                            _DarkDropdown<double>(
                              label: 'AQL',
                              value: _aql,
                              items: aqlValues
                                  .map(
                                    (v) => DropdownMenuItem<double>(
                                      value: v,
                                      child: Text(v.toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _aql = value);
                                _recalcularPlan();
                              },
                            ),
                            const SizedBox(height: 16),
                            if (_errorPlan != null)
                              Text(
                                _errorPlan!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            if (_plan != null) ...[
                              _InfoLine('Método: NCh44:2007', bold: true),
                              _InfoLine('Letra código: ${_plan!.letraCodigo}'),
                              _InfoLine(
                                  'Tamaño de muestra: ${_plan!.tamanoMuestra}'),
                              _InfoLine(
                                _plan!.inspeccion100
                                    ? 'Ac / Re: inspección 100%'
                                    : 'Ac: ${_plan!.ac}   Re: ${_plan!.re}',
                              ),
                              if (_plan!.notaFlecha != null)
                                Text(
                                  _plan!.notaFlecha!,
                                  style: const TextStyle(
                                    color: Color(0xFFFFCC80),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Inspección',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _InfoLine(
                                'Muestra requerida: ${_plan?.tamanoMuestra ?? '-'}'),
                            _InfoLine(
                                'Unidades NC registradas: ${_hallazgos.length}'),
                            _InfoLine(
                              _plan == null || _plan!.inspeccion100
                                  ? 'Ac / Re: inspección 100%'
                                  : 'Ac: ${_plan!.ac}   Re: ${_plan!.re}',
                            ),
                            _InfoLine('Defectos registrados: $_defectosTotales'),
                            const SizedBox(height: 16),
                            if (_procesoPt == null)
                              const Text(
                                'Seleccione el Proceso PT para registrar hallazgos.',
                                style: TextStyle(color: Color(0xFFB0BEC5)),
                              )
                            else if (_cargandoCatalogoProceso)
                              const Center(child: CircularProgressIndicator())
                            else ...[
                              for (var i = 0; i < _hallazgos.length; i++)
                                _HallazgoCard(
                                  index: i,
                                  hallazgo: _hallazgos[i],
                                  parametrosVisuales: _parametrosVisuales,
                                  origenesProblema: _origenesProblema,
                                  onTomarFoto: () =>
                                      _tomarFotoHallazgo(_hallazgos[i]),
                                  onSeleccionarArchivo: () =>
                                      _seleccionarArchivoHallazgo(
                                          _hallazgos[i]),
                                  onEliminar: () => _quitarHallazgo(i),
                                  onChanged: () => setState(() {}),
                                ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _agregarHallazgo,
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar hallazgo'),
                                style: _outlinedStyle,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _guardando ? null : _finalizarInspeccion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8BC34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _guardando
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  'FINALIZAR INSPECCIÓN',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final ButtonStyle _outlinedStyle = OutlinedButton.styleFrom(
  padding: const EdgeInsets.symmetric(vertical: 16),
  foregroundColor: Colors.white,
  side: const BorderSide(color: Color(0xFF8BC34A)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _HallazgoCard extends StatelessWidget {
  final int index;
  final _Hallazgo hallazgo;
  final List<Map<String, dynamic>> parametrosVisuales;
  final List<Map<String, dynamic>> origenesProblema;
  final VoidCallback onTomarFoto;
  final VoidCallback onSeleccionarArchivo;
  final VoidCallback onEliminar;
  final VoidCallback onChanged;

  const _HallazgoCard({
    required this.index,
    required this.hallazgo,
    required this.parametrosVisuales,
    required this.origenesProblema,
    required this.onTomarFoto,
    required this.onSeleccionarArchivo,
    required this.onEliminar,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17212B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF37474F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hallazgo ${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: onEliminar,
                icon: const Icon(Icons.delete_outline,
                    color: Color(0xFFE57373)),
              ),
            ],
          ),
          const Text(
            'Defectos (máximo 3)',
            style: TextStyle(color: Color(0xFFB0BEC5), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: parametrosVisuales.map((p) {
              final id = p['id'] as int;
              final selected = hallazgo.defectoIds.contains(id);

              return FilterChip(
                label: Text(p['nombre'].toString()),
                selected: selected,
                onSelected: (value) {
                  if (value && hallazgo.defectoIds.length >= 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Máximo 3 defectos por hallazgo')),
                    );
                    return;
                  }

                  if (value) {
                    hallazgo.defectoIds.add(id);
                  } else {
                    hallazgo.defectoIds.remove(id);
                  }
                  onChanged();
                },
                selectedColor: const Color(0xFFE57373),
                backgroundColor: const Color(0xFFEEF3F5),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF263238),
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _DarkDropdown<int>(
            label: 'Origen',
            value: hallazgo.origenId,
            items: origenesProblema
                .map(
                  (o) => DropdownMenuItem<int>(
                    value: o['id'] as int,
                    child: Text(o['nombre'].toString()),
                  ),
                )
                .toList(),
            onChanged: (value) {
              hallazgo.origenId = value;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: hallazgo.observacionController,
            maxLength: 120,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Observación',
              labelStyle: TextStyle(color: Color(0xFFB0BEC5)),
              counterStyle: TextStyle(color: Color(0xFFB0BEC5)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF546E7A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF8BC34A)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onTomarFoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Tomar foto'),
                  style: _outlinedStyle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSeleccionarArchivo,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Archivo'),
                  style: _outlinedStyle,
                ),
              ),
            ],
          ),
          if (hallazgo.fotoNombre != null) ...[
            const SizedBox(height: 8),
            Text(
              'Foto: ${hallazgo.fotoNombre}',
              style: const TextStyle(
                  color: Color(0xFFCFD8DC), fontWeight: FontWeight.bold),
            ),
          ] else
            const Text(
              'Foto obligatoria',
              style: TextStyle(color: Color(0xFFE57373), fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String text;
  final bool bold;

  const _InfoLine(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFFCFD8DC),
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const _DarkTextField({
    this.controller,
    required this.label,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFB0BEC5)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF546E7A)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF8BC34A)),
        ),
      ),
    );
  }
}

class _DarkDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DarkDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: const Color(0xFF1F2A33),
      isExpanded: true,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFFB0BEC5)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF546E7A)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF8BC34A)),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1F2A33).withOpacity(0.90),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}
