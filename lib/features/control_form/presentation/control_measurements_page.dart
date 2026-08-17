import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/control_api.dart';
import '../../../core/api/orden_fabricacion_api.dart';
import '../../../core/local/pending_records_store.dart';
import '../../../core/network/network_mode_service.dart';
import '../../../core/utils/turno_calculator.dart';
import '../domain/control_context.dart';

class ControlMeasurementsPage extends StatefulWidget {
  final ControlContext controlContext;
  final String np;
  final List<String> selectedFailures;
  final bool visualValidatedWithoutFailures;
  final String observation;
  final List<Map<String, dynamic>> bobinas;
  final int? tipoOndaId;
  final bool requiereMerma;
  final String? tipoMerma;
  final String? cantidadMerma;
  final String? cliente;
  final String? productCode;
  final String? productDescription;
  final String? origenId;

  const ControlMeasurementsPage({
    super.key,
    required this.controlContext,
    required this.np,
    required this.selectedFailures,
    required this.visualValidatedWithoutFailures,
    required this.observation,
    this.bobinas = const [],
    this.tipoOndaId,
    this.requiereMerma = false,
    this.tipoMerma,
    this.cantidadMerma,
    this.cliente,
    this.productCode,
    this.productDescription,
    this.origenId,
  });

  @override
  State<ControlMeasurementsPage> createState() =>
      _ControlMeasurementsPageState();
}

class _ControlMeasurementsPageState extends State<ControlMeasurementsPage> {
  final ControlApi _controlApi = ControlApi();
  final OrdenFabricacionApi _ordenFabricacionApi = OrdenFabricacionApi();
  final PendingRecordsStore _pendingRecordsStore = PendingRecordsStore();
  final NetworkModeService _networkModeService = NetworkModeService();

  final ImagePicker _imagePicker = ImagePicker();

  Uint8List? _selectedAttachmentBytes;
  String? _selectedAttachmentName;

  String? _productCode;
  String? _productDescription;
  String? _cliente;
  bool _buscandoOrden = false;
  List<Map<String, dynamic>> _ordenItems = [];
  String? _selectedOrdenItem;

  bool _hasLabTest = false;

  @override
  void initState() {
    super.initState();

    // Si el producto ya fue buscado/seleccionado en la pantalla anterior
    // (ControlFormPage), se reutiliza acá para no obligar al operador a
    // repetir la búsqueda por NP. Si no vino nada (o quiere cambiarlo),
    // sigue disponible el botón "Buscar" de esta misma pantalla.
    _cliente = widget.cliente;
    _productCode = widget.productCode;
    _productDescription = widget.productDescription;
    _selectedOrdenItem = widget.productCode;
  }

  Future<void> _buscarItemsPorNp() async {
    final np = widget.np.trim();

    if (np.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay NP para buscar')),
      );
      return;
    }

    setState(() {
      _buscandoOrden = true;
    });

    try {
      final data = await _ordenFabricacionApi.obtenerOrdenFabricacion(
        np,
        proceso: widget.controlContext.processName,
      );

      if (!mounted) return;

      final items = List<Map<String, dynamic>>.from(
        (data['items'] as List?) ?? [],
      );

      setState(() {
        _cliente = data['cliente']?.toString();
        _ordenItems = items;

        // Mismo criterio que ControlFormPage: con un único ítem se
        // autoselecciona; con 2+ requiere selección manual del operador.
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
          const SnackBar(
            content: Text('No se encontraron ítems para este NP'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo consultar el NP. Puede continuar manualmente.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _buscandoOrden = false;
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );

    if (photo == null) return;

    final bytes = await photo.readAsBytes();

    setState(() {
      _selectedAttachmentBytes = bytes;
      _selectedAttachmentName = photo.name;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    setState(() {
      _selectedAttachmentBytes = result.files.single.bytes;
      _selectedAttachmentName = result.files.single.name;
    });
  }

  void _removeAttachment() {
    setState(() {
      _selectedAttachmentBytes = null;
      _selectedAttachmentName = null;
    });
  }

  Future<void> _saveControl() async {
    // Red de seguridad: si hay ítems de la búsqueda por NP pero ninguno
    // quedó seleccionado, no se permite guardar con codigoProducto/
    // descripcionProducto en null.
    if (_ordenItems.isNotEmpty && _productCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar el ítem del NP antes de guardar'),
        ),
      );
      return;
    }

    final bool isNoConforme = !widget.visualValidatedWithoutFailures;

    if (widget.controlContext.processId == 7 &&
        isNoConforme &&
        _selectedAttachmentBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debe adjuntar una foto cuando el resultado es No Conforme',
          ),
        ),
      );
      return;
    }

    if (widget.controlContext.processId == 7 && isNoConforme) {
      final seleccionoOtro = widget.controlContext.parametrosVisuales.any(
        (parametro) =>
            widget.selectedFailures.contains(parametro['id'].toString()) &&
            parametro['nombre'].toString().startsWith('Otro'),
      );

      if (seleccionoOtro && widget.observation.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debe ingresar una observación al seleccionar "Otro"',
            ),
          ),
        );
        return;
      }
    }

    const int actionId = 1;

    final payload = {
      'usuarioId': widget.controlContext.userId,
      'procesoId': widget.controlContext.processId,
      'maquinaId': widget.controlContext.machineId,
      'formularioId': widget.controlContext.formId,
      'area': widget.controlContext.operatorArea,
      'np': widget.np,
      'cliente': _cliente,
      'codigoProducto': _productCode,
      'descripcionProducto': _productDescription,
      'tipoOndaId': widget.tipoOndaId,
      'turno': calcularTurno(DateTime.now()),
      'resultadoVisual':
          widget.visualValidatedWithoutFailures ? 'Cumple' : 'No Cumple',
      'observacion': widget.observation,
      'fallasVisuales': isNoConforme
          ? widget.selectedFailures
              .map(
                (id) => {
                  'parametroId': int.parse(id),
                  'accionId': actionId,
                  'observacion': widget.observation,
                },
              )
              .toList()
          : [],
      'requiereEnsayoLaboratorio': _hasLabTest,
      'ensayosLaboratorio': [],
      'requiereMerma': widget.requiereMerma,
      'tipoMerma': widget.tipoMerma,
      'cantidadMerma': widget.cantidadMerma,
      'origenId':
          widget.origenId != null ? int.tryParse(widget.origenId!) : null,
      'bobinas': widget.bobinas,
    };

    final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

    if (shouldUseOffline && _selectedAttachmentBytes != null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede guardar evidencia sin conexión. Revise conexión e intente nuevamente.',
          ),
        ),
      );

      return;
    }

    try {
      await _controlApi.guardarRegistro(
        payload,
        archivoBytes: _selectedAttachmentBytes,
        archivoNombre: _selectedAttachmentName,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Control calidad guardado correctamente'),
        ),
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (_selectedAttachmentBytes != null) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar con evidencia. Revise conexión e intente nuevamente.',
            ),
          ),
        );

        return;
      }

      await _pendingRecordsStore.savePendingRecord(payload);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión. Registro guardado localmente para sincronizar.',
          ),
        ),
      );

      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2A33),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mediciones y Cierre'),
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
                            Text(
                              widget.controlContext.machineName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Proceso: ${widget.controlContext.processName}',
                              style: const TextStyle(
                                color: Color(0xFFCFD8DC),
                              ),
                            ),
                            Text(
                              'NP: ${widget.np}',
                              style: const TextStyle(
                                color: Color(0xFFCFD8DC),
                              ),
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
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              label: const Text('Buscar ítems del NP'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0xFF8BC34A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            if (_cliente != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Cliente: $_cliente',
                                style: const TextStyle(
                                  color: Color(0xFFCFD8DC),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            if (_ordenItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedOrdenItem,
                                dropdownColor: const Color(0xFFEEF3F5),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Ítem del NP',
                                  labelStyle: TextStyle(
                                    color: Color(0xFFB0BEC5),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF546E7A),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF8BC34A),
                                    ),
                                  ),
                                ),
                                items: _ordenItems
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item['codigo'].toString(),
                                        child: Text(
                                          '${item['codigo']} - ${item['nombre'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF263238),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  final item = _ordenItems.firstWhere(
                                    (element) =>
                                        element['codigo'].toString() == value,
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
                              const SizedBox(height: 12),
                              Text(
                                'Código: $_productCode',
                                style: const TextStyle(
                                  color: Color(0xFFCFD8DC),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_productDescription != null)
                                Text(
                                  'Producto: $_productDescription',
                                  style: const TextStyle(
                                    color: Color(0xFFCFD8DC),
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
                              'Registrar ensayo laboratorio',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF8BC34A),
                              title: const Text(
                                'Sí',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: true,
                              groupValue: _hasLabTest,
                              onChanged: (value) {
                                setState(() {
                                  _hasLabTest = value ?? false;
                                });
                              },
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF8BC34A),
                              title: const Text(
                                'No',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: false,
                              groupValue: _hasLabTest,
                              onChanged: (value) {
                                setState(() {
                                  _hasLabTest = value ?? false;
                                });
                              },
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
                              'Evidencia fotográfica',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Adjunte foto o archivo PDF/JPG/PNG. Obligatoria si el resultado es No Conforme.',
                              style: TextStyle(color: Color(0xFFB0BEC5)),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Tomar foto'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                foregroundColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0xFF8BC34A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.attach_file),
                              label: const Text('Seleccionar archivo'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                foregroundColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0xFF8BC34A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            if (_selectedAttachmentName != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'Archivo: $_selectedAttachmentName',
                                style: const TextStyle(
                                  color: Color(0xFFCFD8DC),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _removeAttachment,
                                icon: const Icon(Icons.close),
                                label: const Text('Quitar archivo'),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFFFCC80),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _saveControl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8BC34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'GUARDAR CONTROL',
                            style: TextStyle(
                              fontSize: 22,
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

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1F2A33).withOpacity(0.90),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: child,
      ),
    );
  }
}
