import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/calidad_faret_api.dart';
import '../../../core/network/network_mode_service.dart';
import '../domain/calidad_faret_catalog.dart';

class CalidadFaretFormPage extends StatefulWidget {
  const CalidadFaretFormPage({super.key});

  @override
  State<CalidadFaretFormPage> createState() => _CalidadFaretFormPageState();
}

class _CalidadFaretFormPageState extends State<CalidadFaretFormPage> {
  final CalidadFaretApi _calidadFaretApi = CalidadFaretApi();
  final NetworkModeService _networkModeService = NetworkModeService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nvFaretController = TextEditingController();
  final TextEditingController _nPliegoController = TextEditingController();
  final TextEditingController _nPasadaController = TextEditingController();
  final TextEditingController _nItemController = TextEditingController();
  final TextEditingController _pliegoControlNController =
      TextEditingController();
  final TextEditingController _operadorOtroController =
      TextEditingController();
  final TextEditingController _accionCorrectivaController =
      TextEditingController();

  bool? _nvVoBoAprobado;
  String? _selectedAreaControl;
  String? _selectedOperador;
  String? _selectedMaquina;

  bool _presentaDefectos = false;
  String? _selectedAreaDefecto;
  final Set<String> _selectedDefectos = {};
  String? _selectedTipoFolia;

  final List<Uint8List> _attachmentsBytes = [];
  final List<String> _attachmentsNames = [];

  bool _saving = false;

  @override
  void dispose() {
    _nvFaretController.dispose();
    _nPliegoController.dispose();
    _nPasadaController.dispose();
    _nItemController.dispose();
    _pliegoControlNController.dispose();
    _operadorOtroController.dispose();
    _accionCorrectivaController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _takePhoto() async {
    if (_attachmentsBytes.length >= 5) {
      _showSnack('Máximo 5 archivos de evidencia');
      return;
    }

    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );

    if (photo == null) return;

    final bytes = await photo.readAsBytes();

    setState(() {
      _attachmentsBytes.add(bytes);
      _attachmentsNames.add(photo.name);
    });
  }

  Future<void> _pickFiles() async {
    if (_attachmentsBytes.length >= 5) {
      _showSnack('Máximo 5 archivos de evidencia');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );

    if (result == null) return;

    setState(() {
      for (final file in result.files) {
        if (_attachmentsBytes.length >= 5) break;
        if (file.bytes == null) continue;

        _attachmentsBytes.add(file.bytes!);
        _attachmentsNames.add(file.name);
      }
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachmentsBytes.removeAt(index);
      _attachmentsNames.removeAt(index);
    });
  }

  Future<void> _guardarRegistro() async {
    if (_nvFaretController.text.trim().isEmpty) {
      _showSnack('Debe ingresar NV FARET');
      return;
    }

    if (_nvVoBoAprobado == null) {
      _showSnack('Debe indicar si el NV tiene V°B° aprobado');
      return;
    }

    if (_nPliegoController.text.trim().isEmpty) {
      _showSnack('Debe ingresar N° de pliego');
      return;
    }

    if (_nPasadaController.text.trim().isEmpty) {
      _showSnack('Debe ingresar N° de pasada');
      return;
    }

    if (_nItemController.text.trim().isEmpty) {
      _showSnack('Debe ingresar N° de item');
      return;
    }

    if (_pliegoControlNController.text.trim().isEmpty) {
      _showSnack('Debe ingresar el pliego de control N°');
      return;
    }

    if (_selectedAreaControl == null) {
      _showSnack('Debe seleccionar el área de control');
      return;
    }

    if (_selectedOperador == null) {
      _showSnack('Debe seleccionar operador');
      return;
    }

    if (_selectedOperador == 'Otros' &&
        _operadorOtroController.text.trim().isEmpty) {
      _showSnack('Debe indicar el nombre del operador');
      return;
    }

    if (_selectedMaquina == null) {
      _showSnack('Debe seleccionar máquina');
      return;
    }

    if (_presentaDefectos) {
      if (_selectedAreaDefecto == null) {
        _showSnack('Debe seleccionar el área donde se encontró el defecto');
        return;
      }

      if (_selectedDefectos.isEmpty) {
        _showSnack('Debe seleccionar al menos un defecto');
        return;
      }

      if (_selectedAreaDefecto == '05-FOLIA' && _selectedTipoFolia == null) {
        _showSnack('Debe seleccionar el tipo de folia');
        return;
      }

      if (_accionCorrectivaController.text.trim().isEmpty) {
        _showSnack('Debe indicar la acción correctiva');
        return;
      }
    }

    final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

    if (shouldUseOffline) {
      _showSnack(
        'Sin conexión. Este formulario requiere conexión para guardar.',
      );
      return;
    }

    final payload = {
      'nvFaret': _nvFaretController.text.trim(),
      'nvVoBoAprobado': _nvVoBoAprobado,
      'nPliego': _nPliegoController.text.trim(),
      'nPasada': _nPasadaController.text.trim(),
      'nItem': _nItemController.text.trim(),
      'pliegoControlN': _pliegoControlNController.text.trim(),
      'areaControl': _selectedAreaControl,
      'operador': _selectedOperador,
      'operadorOtro': _selectedOperador == 'Otros'
          ? _operadorOtroController.text.trim()
          : null,
      'maquina': _selectedMaquina,
      'presentaDefectos': _presentaDefectos,
      'areaDefecto': _presentaDefectos ? _selectedAreaDefecto : null,
      'defectos': _presentaDefectos ? _selectedDefectos.toList() : [],
      'tipoFolia': _presentaDefectos && _selectedAreaDefecto == '05-FOLIA'
          ? _selectedTipoFolia
          : null,
      'accionCorrectiva':
          _presentaDefectos ? _accionCorrectivaController.text.trim() : null,
    };

    setState(() {
      _saving = true;
    });

    try {
      await _calidadFaretApi.guardarRegistro(
        payload,
        archivosBytes: _attachmentsBytes,
        archivosNombres: _attachmentsNames,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro guardado correctamente')),
      );

      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;

      _showSnack('No se pudo guardar. Revise conexión e intente nuevamente.');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF78909C)),
      labelStyle: const TextStyle(color: Color(0xFFB0BEC5)),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF546E7A)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF8BC34A)),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFFEEF3F5),
      isExpanded: true,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      selectedItemBuilder: (context) {
        return items.map((item) {
          return Text(
            item,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          );
        }).toList();
      },
      decoration: _fieldDecoration(label),
      items: items
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
      onChanged: onChanged,
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor:
            selected ? const Color(0xFFE57373) : const Color(0xFFEEF3F5),
        side: BorderSide(
          color: selected ? const Color(0xFFE57373) : const Color(0xFF8FA3AD),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: selected ? Colors.white : const Color(0xFF263238),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final operadores = _selectedAreaControl == null
        ? const <String>[]
        : CalidadFaretCatalog.operadoresPorArea[_selectedAreaControl] ??
            const <String>[];

    final maquinas = _selectedAreaControl == null
        ? const <String>[]
        : CalidadFaretCatalog.maquinasPorArea[_selectedAreaControl] ??
            const <String>[];

    final defectosDisponibles = _selectedAreaDefecto == null
        ? const <String>[]
        : CalidadFaretCatalog.defectosPorArea[_selectedAreaDefecto] ??
            const <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2A33),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Calidad Faret'),
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
                          children: const [
                            Text(
                              'Control de Calidad en Procesos Productivos',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'CDP-CC-IOF V02',
                              style: TextStyle(color: Color(0xFFB0BEC5)),
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
                              controller: _nvFaretController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration('NV FARET'),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '¿NV tiene V°B° aprobado?',
                              style: TextStyle(
                                color: Color(0xFFB0BEC5),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF8BC34A),
                              title: const Text(
                                'SI',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: true,
                              groupValue: _nvVoBoAprobado,
                              onChanged: (value) {
                                setState(() {
                                  _nvVoBoAprobado = value;
                                });
                              },
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF8BC34A),
                              title: const Text(
                                'NO',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: false,
                              groupValue: _nvVoBoAprobado,
                              onChanged: (value) {
                                setState(() {
                                  _nvVoBoAprobado = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nPliegoController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration('N° de pliego'),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nPasadaController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration('N° de pasada'),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nItemController,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDecoration(
                                'N° de item',
                                hint: 'Si es más de uno, separados por guion',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _pliegoControlNController,
                              style: const TextStyle(color: Colors.white),
                              decoration:
                                  _fieldDecoration('Pliego de control N°'),
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
                              'Área de control',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _dropdown(
                              label: 'Área de control',
                              value: _selectedAreaControl,
                              items: CalidadFaretCatalog.areasControl,
                              onChanged: (value) {
                                setState(() {
                                  _selectedAreaControl = value;
                                  _selectedOperador = null;
                                  _operadorOtroController.clear();
                                  _selectedMaquina = null;
                                });
                              },
                            ),
                            if (_selectedAreaControl != null) ...[
                              const SizedBox(height: 16),
                              _dropdown(
                                label: 'Operador',
                                value: _selectedOperador,
                                items: operadores,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedOperador = value;
                                    _operadorOtroController.clear();
                                  });
                                },
                              ),
                              if (_selectedOperador == 'Otros') ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _operadorOtroController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _fieldDecoration(
                                    'Nombre del operador',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              _dropdown(
                                label: 'Máquina',
                                value: _selectedMaquina,
                                items: maquinas,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMaquina = value;
                                  });
                                },
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
                              '¿El pliego de control presenta defectos?',
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
                                'NO',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: false,
                              groupValue: _presentaDefectos,
                              onChanged: (value) {
                                setState(() {
                                  _presentaDefectos = value ?? false;

                                  if (!_presentaDefectos) {
                                    _selectedAreaDefecto = null;
                                    _selectedDefectos.clear();
                                    _selectedTipoFolia = null;
                                    _accionCorrectivaController.clear();
                                    _attachmentsBytes.clear();
                                    _attachmentsNames.clear();
                                  }
                                });
                              },
                            ),
                            RadioListTile<bool>(
                              contentPadding: EdgeInsets.zero,
                              activeColor: const Color(0xFF8BC34A),
                              title: const Text(
                                'SI',
                                style: TextStyle(color: Colors.white),
                              ),
                              value: true,
                              groupValue: _presentaDefectos,
                              onChanged: (value) {
                                setState(() {
                                  _presentaDefectos = value ?? false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_presentaDefectos) ...[
                        const SizedBox(height: 16),
                        _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Área donde se encontró el defecto',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _dropdown(
                                label: 'Área del defecto',
                                value: _selectedAreaDefecto,
                                items: CalidadFaretCatalog.areasControl,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedAreaDefecto = value;
                                    _selectedDefectos.clear();
                                    _selectedTipoFolia = null;
                                  });
                                },
                              ),
                              if (_selectedAreaDefecto != null) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  'Defectos encontrados',
                                  style: TextStyle(
                                    color: Color(0xFFB0BEC5),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: defectosDisponibles.map((defecto) {
                                    final selected =
                                        _selectedDefectos.contains(defecto);

                                    return _toggleChip(defecto, selected, () {
                                      setState(() {
                                        if (selected) {
                                          _selectedDefectos.remove(defecto);
                                        } else {
                                          _selectedDefectos.add(defecto);
                                        }
                                      });
                                    });
                                  }).toList(),
                                ),
                              ],
                              if (_selectedAreaDefecto == '05-FOLIA') ...[
                                const SizedBox(height: 16),
                                _dropdown(
                                  label: 'Tipo de folia',
                                  value: _selectedTipoFolia,
                                  items: CalidadFaretCatalog.tiposFolia,
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedTipoFolia = value;
                                    });
                                  },
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
                                'Evidencia del defecto',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Puede adjuntar hasta 5 fotos o archivos PDF/JPG/PNG.',
                                style: TextStyle(color: Color(0xFFB0BEC5)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _takePhoto,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Tomar foto'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF8BC34A),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _pickFiles,
                                icon: const Icon(Icons.attach_file),
                                label: const Text('Seleccionar archivos'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFF8BC34A),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                              if (_attachmentsNames.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                for (var i = 0;
                                    i < _attachmentsNames.length;
                                    i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _attachmentsNames[i],
                                            style: const TextStyle(
                                              color: Color(0xFFCFD8DC),
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () =>
                                              _removeAttachment(i),
                                          icon: const Icon(
                                            Icons.close,
                                            color: Color(0xFFFFCC80),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          child: TextField(
                            controller: _accionCorrectivaController,
                            maxLines: 3,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecoration(
                              'Acción correctiva',
                              hint: 'Indicar la acción realizada',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _guardarRegistro,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8BC34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _saving ? 'GUARDANDO...' : 'GUARDAR REGISTRO',
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
