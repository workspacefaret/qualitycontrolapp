import 'package:flutter/material.dart';

import '../../../core/api/calidad_faret_pallet_api.dart';
import '../domain/calidad_faret_catalog.dart';

class CalidadFaretPalletFormPage extends StatefulWidget {
  final String? operador;

  const CalidadFaretPalletFormPage({super.key, this.operador});

  @override
  State<CalidadFaretPalletFormPage> createState() =>
      _CalidadFaretPalletFormPageState();
}

class _CalidadFaretPalletFormPageState
    extends State<CalidadFaretPalletFormPage> {
  final CalidadFaretPalletApi _api = CalidadFaretPalletApi();

  final TextEditingController _dimensionController = TextEditingController();
  final TextEditingController _fibraController = TextEditingController();
  final TextEditingController _numeroPalletController =
      TextEditingController();
  final TextEditingController _observacionesController =
      TextEditingController();

  String? _tipoMaterial;
  String? _selectedAreaControl;
  String? _selectedMaquina;
  String? _numeroPasadasPrensa;

  bool _loadingPreguntas = true;
  bool _saving = false;
  String? _loadError;

  List<Map<String, dynamic>> _preguntas = [];
  final Map<int, String?> _resultados = {};
  final Map<int, TextEditingController> _observacionControllers = {};

  @override
  void initState() {
    super.initState();
    _cargarPreguntas();
  }

  @override
  void dispose() {
    _dimensionController.dispose();
    _fibraController.dispose();
    _numeroPalletController.dispose();
    _observacionesController.dispose();

    for (final controller in _observacionControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> _cargarPreguntas() async {
    try {
      final preguntas = await _api.obtenerPreguntas();

      if (!mounted) return;

      setState(() {
        _preguntas = preguntas;

        for (final pregunta in preguntas) {
          final id = pregunta['id'] as int;
          _resultados[id] = null;
          _observacionControllers[id] = TextEditingController();
        }

        _loadingPreguntas = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadError = 'No se pudo cargar el checklist. Revise su conexión.';
        _loadingPreguntas = false;
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _setResultado(int preguntaId, String resultado) {
    setState(() {
      _resultados[preguntaId] = resultado;

      if (resultado == 'CUMPLE') {
        _observacionControllers[preguntaId]?.clear();
      }
    });
  }

  void _marcarTodasComoCumple() {
    setState(() {
      for (final pregunta in _preguntas) {
        final id = pregunta['id'] as int;
        _resultados[id] = 'CUMPLE';
        _observacionControllers[id]?.clear();
      }
    });
  }

  int get _respondidas =>
      _resultados.values.where((resultado) => resultado != null).length;

  int get _totalCumple =>
      _resultados.values.where((resultado) => resultado == 'CUMPLE').length;

  int get _totalNoCumple => _resultados.values
      .where((resultado) => resultado == 'NO_CUMPLE')
      .length;

  Future<void> _revisarYGuardar() async {
    if (_tipoMaterial == null) {
      _showSnack('Debe seleccionar el tipo de material');
      return;
    }

    if (_dimensionController.text.trim().isEmpty) {
      _showSnack('Debe ingresar la dimensión');
      return;
    }

    if (_numeroPalletController.text.trim().isEmpty) {
      _showSnack('Debe ingresar el número de pallet');
      return;
    }

    if (_respondidas < _preguntas.length) {
      _showSnack('Debe responder todas las preguntas del checklist');
      return;
    }

    for (final pregunta in _preguntas) {
      final id = pregunta['id'] as int;

      if (_resultados[id] == 'NO_CUMPLE' &&
          (_observacionControllers[id]?.text.trim().isEmpty ?? true)) {
        _showSnack(
          'Debe ingresar observación para "${pregunta['texto']}"',
        );
        return;
      }
    }

    final confirmado = await _mostrarResumen();

    if (confirmado != true) return;

    final payload = {
      'tipoMaterial': _tipoMaterial,
      'dimension': _dimensionController.text.trim(),
      'fibra': _fibraController.text.trim().isEmpty
          ? null
          : _fibraController.text.trim(),
      'numeroPallet': _numeroPalletController.text.trim(),
      'numeroPasadasPrensa': _numeroPasadasPrensa == null
          ? null
          : int.parse(_numeroPasadasPrensa!),
      'observaciones': _observacionesController.text.trim().isEmpty
          ? null
          : _observacionesController.text.trim(),
      'areaControl': _selectedAreaControl,
      'operador': widget.operador,
      'maquina': _selectedMaquina,
      'respuestas': _preguntas.map((pregunta) {
        final id = pregunta['id'] as int;

        return {
          'preguntaId': id,
          'resultado': _resultados[id],
          'observacion': _observacionControllers[id]?.text.trim().isEmpty ??
                  true
              ? null
              : _observacionControllers[id]!.text.trim(),
        };
      }).toList(),
    };

    setState(() {
      _saving = true;
    });

    try {
      await _api.guardarRegistro(payload);

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

  Future<bool?> _mostrarResumen() {
    final noCumpleItems = _preguntas.where((pregunta) {
      return _resultados[pregunta['id'] as int] == 'NO_CUMPLE';
    }).toList();

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2A33),
          title: const Text(
            'Resumen del checklist',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cumple: $_totalCumple   /   No cumple: $_totalNoCumple',
                    style: const TextStyle(
                      color: Color(0xFFB0BEC5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (noCumpleItems.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Observaciones:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final pregunta in noCumpleItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• ${pregunta['texto']}: '
                          '${_observacionControllers[pregunta['id'] as int]?.text.trim()}',
                          style: const TextStyle(color: Color(0xFFCFD8DC)),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8BC34A),
                foregroundColor: Colors.white,
              ),
              child: const Text('CONFIRMAR Y GUARDAR'),
            ),
          ],
        );
      },
    );
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

  Widget _bigToggleButton(
    String label,
    bool selected,
    Color selectedColor,
    VoidCallback onTap,
  ) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor:
              selected ? selectedColor : const Color(0xFFEEF3F5),
          side: BorderSide(
            color: selected ? selectedColor : const Color(0xFF8FA3AD),
            width: selected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : const Color(0xFF263238),
          ),
        ),
      ),
    );
  }

  Widget _buildPreguntaCard(Map<String, dynamic> pregunta) {
    final id = pregunta['id'] as int;
    final texto = pregunta['texto'].toString();
    final resultado = _resultados[id];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            texto,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _bigToggleButton(
                  'CUMPLE',
                  resultado == 'CUMPLE',
                  const Color(0xFF8BC34A),
                  () => _setResultado(id, 'CUMPLE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigToggleButton(
                  'NO CUMPLE',
                  resultado == 'NO_CUMPLE',
                  const Color(0xFFE57373),
                  () => _setResultado(id, 'NO_CUMPLE'),
                ),
              ),
            ],
          ),
          if (resultado == 'NO_CUMPLE') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _observacionControllers[id],
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(
                'Observación',
                hint: 'Obligatoria para NO CUMPLE',
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maquinas = _selectedAreaControl == null
        ? const <String>[]
        : CalidadFaretCatalog.maquinasPorArea[_selectedAreaControl] ??
            const <String>[];

    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2A33),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Control Pallet / Papel'),
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
            child: _loadingPreguntas
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _loadingPreguntas = true;
                                    _loadError = null;
                                  });
                                  _cargarPreguntas();
                                },
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _SectionCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Tipo de material',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _bigToggleButton(
                                              'NV (FPS)',
                                              _tipoMaterial == 'NV',
                                              const Color(0xFF8BC34A),
                                              () => setState(
                                                () => _tipoMaterial = 'NV',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _bigToggleButton(
                                              'PAPEL',
                                              _tipoMaterial == 'PAPEL',
                                              const Color(0xFF8BC34A),
                                              () => setState(
                                                () => _tipoMaterial = 'PAPEL',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _dimensionController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration:
                                            _fieldDecoration('Dimensión'),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _fibraController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _fieldDecoration(
                                          'Fibra',
                                          hint: 'Opcional',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _numeroPalletController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _fieldDecoration(
                                          'N° / identificación de pallet',
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      _dropdown(
                                        label: 'N° de pasadas de prensa',
                                        value: _numeroPasadasPrensa,
                                        items: const ['1', '2', '3'],
                                        onChanged: (value) {
                                          setState(() {
                                            _numeroPasadasPrensa = value;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: _observacionesController,
                                        maxLines: 3,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _fieldDecoration(
                                          'Observaciones',
                                          hint: 'Opcional',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _SectionCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Área y máquina',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Opcional',
                                        style: TextStyle(
                                          color: Color(0xFFB0BEC5),
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
                                            _selectedMaquina = null;
                                          });
                                        },
                                      ),
                                      if (_selectedAreaControl != null) ...[
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Checklist: $_respondidas/'
                                          '${_preguntas.length} respondidas',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _marcarTodasComoCumple,
                                        child: const Text(
                                          'MARCAR TODAS COMO CUMPLE',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                for (final pregunta in _preguntas) ...[
                                  _buildPreguntaCard(pregunta),
                                  const SizedBox(height: 16),
                                ],
                                SizedBox(
                                  height: 64,
                                  child: ElevatedButton(
                                    onPressed:
                                        _saving ? null : _revisarYGuardar,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF8BC34A),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      _saving
                                          ? 'GUARDANDO...'
                                          : 'REVISAR Y GUARDAR',
                                      style: const TextStyle(
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
