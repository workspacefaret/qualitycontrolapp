import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/control_api.dart';
import '../../../core/local/pending_records_store.dart';
import '../../../core/network/network_mode_service.dart';
import '../domain/control_context.dart';
import 'control_measurements_page.dart';
import 'product_qr_scanner_page.dart';

class ControlFormPage extends StatefulWidget {
  final ControlContext controlContext;

  const ControlFormPage({
    super.key,
    required this.controlContext,
  });

  @override
  State<ControlFormPage> createState() => _ControlFormPageState();
}

class _ControlFormPageState extends State<ControlFormPage> {
  final ControlApi _controlApi = ControlApi();
  final PendingRecordsStore _pendingRecordsStore = PendingRecordsStore();
  final NetworkModeService _networkModeService = NetworkModeService();
  final TextEditingController _npController = TextEditingController();
  final TextEditingController _observationController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  File? _selectedAttachment;
  String? _selectedAttachmentName;
  final Set<String> _selectedFailures = {};
  bool _visualValidatedWithoutFailures = false;
  String? _selectedVisualControlResult;
  String? _selectedTipoOndaId;
  String? _productCode;
  String? _productDescription;

  final List<String> _visualControlResults = [
    'Conforme',
    'No Conforme',
  ];

  @override
  void dispose() {
    _npController.dispose();
    _observationController.dispose();
    super.dispose();
  }

  Future<void> _scanProductCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProductQrScannerPage(),
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    try {
      final data = jsonDecode(result);

      setState(() {
        _productCode = data['codigo']?.toString();
        _productDescription = data['descripcion']?.toString();
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR de producto no válido')),
      );
    }
  }

  void _toggleFailure(String parameterId) {
    setState(() {
      _visualValidatedWithoutFailures = false;

      if (_selectedFailures.contains(parameterId)) {
        _selectedFailures.remove(parameterId);
      } else {
        _selectedFailures.add(parameterId);
      }
    });
  }

  void _validateWithoutFailures() {
    setState(() {
      _selectedFailures.clear();
      _visualValidatedWithoutFailures = true;
    });
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );

    if (photo == null) return;

    setState(() {
      _selectedAttachment = File(photo.path);
      _selectedAttachmentName = photo.name;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result == null || result.files.single.path == null) return;

    setState(() {
      _selectedAttachment = File(result.files.single.path!);
      _selectedAttachmentName = result.files.single.name;
    });
  }

  void _removeAttachment() {
    setState(() {
      _selectedAttachment = null;
      _selectedAttachmentName = null;
    });
  }

  Future<void> _goToMeasurements() async {
    if (_npController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe ingresar NP')),
      );
      return;
    }

    if (_selectedVisualControlResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar resultado visual')),
      );
      return;
    }

    if (widget.controlContext.processId == 1 &&
        widget.controlContext.operatorArea == 'PRODUCCION' &&
        _selectedTipoOndaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar tipo de onda')),
      );
      return;
    }

    if (_selectedVisualControlResult == 'No Conforme' &&
        _selectedFailures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un defecto')),
      );
      return;
    }

    if (_selectedVisualControlResult == 'Conforme') {
      _selectedFailures.clear();
      _visualValidatedWithoutFailures = true;

      final payload = {
        'usuarioId': widget.controlContext.userId,
        'procesoId': widget.controlContext.processId,
        'maquinaId': widget.controlContext.machineId,
        'formularioId': widget.controlContext.formId,
        'area': widget.controlContext.operatorArea,
        'np': _npController.text.trim(),
        'codigoProducto': _productCode,
        'descripcionProducto': _productDescription,
        'tipoOndaId': widget.controlContext.processId == 1
            ? int.tryParse(_selectedTipoOndaId ?? '')
            : null,
        'turno': 'A',
        'resultadoVisual':
            _selectedVisualControlResult == 'Conforme' ? 'Cumple' : 'No Cumple',
        'observacion': _observationController.text.trim(),
        'fallasVisuales': [],
      };

      final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

      if (shouldUseOffline && _selectedAttachment != null) {
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
          archivo: _selectedAttachment,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Control guardado correctamente')),
        );

        Navigator.pop(context);
      } catch (_) {
        if (_selectedAttachment != null) {
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

        Navigator.pop(context);
      }

      return;
    }

    if (widget.controlContext.operatorArea == 'PRODUCCION') {
      final payload = {
        'usuarioId': widget.controlContext.userId,
        'procesoId': widget.controlContext.processId,
        'maquinaId': widget.controlContext.machineId,
        'formularioId': widget.controlContext.formId,
        'area': widget.controlContext.operatorArea,
        'np': _npController.text.trim(),
        'codigoProducto': _productCode,
        'descripcionProducto': _productDescription,
        'tipoOndaId': widget.controlContext.processId == 1
            ? int.tryParse(_selectedTipoOndaId ?? '')
            : null,
        'turno': 'A',
        'resultadoVisual':
            _selectedVisualControlResult == 'Conforme' ? 'Cumple' : 'No Cumple',
        'observacion': _observationController.text.trim(),
        'fallasVisuales': _selectedFailures
            .map(
              (id) => {
                'parametroId': int.parse(id),
                'accionId': 1,
                'observacion': _observationController.text.trim(),
              },
            )
            .toList(),
      };

      final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

      if (shouldUseOffline && _selectedAttachment != null) {
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
          archivo: _selectedAttachment,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Control producción guardado correctamente'),
          ),
        );

        Navigator.pop(context);
      } catch (_) {
        if (_selectedAttachment != null) {
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

        Navigator.pop(context);
      }

      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ControlMeasurementsPage(
          controlContext: widget.controlContext,
          np: _npController.text.trim(),
          selectedFailures: _selectedFailures.toList(),
          visualValidatedWithoutFailures: false,
          observation: _observationController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();

    final String currentDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final String currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final String currentUser = widget.controlContext.userName;
    final bool isProduction =
        widget.controlContext.operatorArea == 'PRODUCCION';
    const String currentShift = 'A';
    final bool isCorrugado = widget.controlContext.processId == 1;

    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2A33),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isProduction ? 'Control Producción' : 'Control Calidad',
        ),
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
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.controlContext.processName,
                              style: const TextStyle(
                                fontSize: 18,
                                color: Color(0xFFB0BEC5),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Fecha: $currentDate',
                              style: const TextStyle(color: Color(0xFFCFD8DC)),
                            ),
                            Text(
                              'Hora: $currentTime',
                              style: const TextStyle(color: Color(0xFFCFD8DC)),
                            ),
                            Text(
                              'Usuario: $currentUser',
                              style: const TextStyle(color: Color(0xFFCFD8DC)),
                            ),
                            Text(
                              'Turno: $currentShift',
                              style: const TextStyle(color: Color(0xFFCFD8DC)),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: isProduction
                                    ? const Color(0xFFFFA726).withOpacity(0.18)
                                    : const Color(0xFF64B5F6).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isProduction
                                      ? const Color(0xFFFFA726)
                                      : const Color(0xFF64B5F6),
                                ),
                              ),
                              child: Text(
                                isProduction
                                    ? 'ÁREA PRODUCCIÓN'
                                    : 'ÁREA CALIDAD',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isProduction
                                      ? const Color(0xFFFFCC80)
                                      : const Color(0xFF90CAF9),
                                ),
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
                            TextField(
                              controller: _npController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'NP',
                                labelStyle: TextStyle(color: Color(0xFFB0BEC5)),
                                enabledBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF546E7A)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF8BC34A)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _scanProductCode,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Escanear Código Producto'),
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
                                  style:
                                      const TextStyle(color: Color(0xFFCFD8DC)),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isCorrugado && isProduction) ...[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Corrugado',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                value: _selectedTipoOndaId,
                                dropdownColor: const Color(0xFFEEF3F5),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                selectedItemBuilder: (context) {
                                  return widget.controlContext.tiposOnda
                                      .map((item) {
                                    return Text(
                                      item['nombre'].toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  }).toList();
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de onda',
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
                                items: widget.controlContext.tiposOnda
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item['id'].toString(),
                                        child: Text(
                                          item['nombre'].toString(),
                                          style: const TextStyle(
                                            color: Color(0xFF263238),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedTipoOndaId = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Resultado visual',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedVisualControlResult,
                              dropdownColor: const Color(0xFFEEF3F5),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              selectedItemBuilder: (context) {
                                return _visualControlResults.map((item) {
                                  return Text(
                                    item,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                }).toList();
                              },
                              decoration: const InputDecoration(
                                labelText: 'Resultado',
                                labelStyle: TextStyle(color: Color(0xFFB0BEC5)),
                                enabledBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF546E7A)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF8BC34A)),
                                ),
                              ),
                              items: _visualControlResults
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                          color: Color(0xFF263238),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedVisualControlResult = value;

                                  if (value == 'Conforme') {
                                    _selectedFailures.clear();
                                    _visualValidatedWithoutFailures = true;
                                  } else {
                                    _visualValidatedWithoutFailures = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_selectedVisualControlResult == 'No Conforme') ...[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Tipo de defecto',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Seleccione máximo 3 defectos',
                                style: TextStyle(color: Color(0xFFB0BEC5)),
                              ),
                              const SizedBox(height: 12),
                              for (final parameter
                                  in widget.controlContext.parametrosVisuales)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      final parameterId =
                                          parameter['id'].toString();

                                      if (!_selectedFailures
                                              .contains(parameterId) &&
                                          _selectedFailures.length >= 3) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Puede seleccionar máximo 3 defectos'),
                                          ),
                                        );
                                        return;
                                      }

                                      _toggleFailure(parameterId);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 18),
                                      backgroundColor:
                                          _selectedFailures.contains(
                                                  parameter['id'].toString())
                                              ? const Color(0xFFE57373)
                                              : const Color(0xFFEEF3F5),
                                      side: BorderSide(
                                        color: _selectedFailures.contains(
                                                parameter['id'].toString())
                                            ? const Color(0xFFE57373)
                                            : const Color(0xFF8FA3AD),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      parameter['nombre'].toString(),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedFailures.contains(
                                                parameter['id'].toString())
                                            ? Colors.white
                                            : const Color(0xFF263238),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _SectionCard(
                        child: TextField(
                          controller: _observationController,
                          maxLength: 120,
                          maxLines: 3,
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
                      ),
                      const SizedBox(height: 16),
                      if (isProduction) ...[
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Evidencia opcional',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Puede adjuntar una foto o archivo PDF/JPG/PNG.',
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
                                  side: const BorderSide(
                                      color: Color(0xFF8BC34A)),
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
                                  side: const BorderSide(
                                      color: Color(0xFF8BC34A)),
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
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _goToMeasurements,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8BC34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            widget.controlContext.operatorArea == 'PRODUCCION'
                                ? 'GUARDAR CONTROL'
                                : 'SIGUIENTE',
                            style: const TextStyle(
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
