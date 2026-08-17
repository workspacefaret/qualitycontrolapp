import 'package:flutter/material.dart';
import '../../core/api/catalogos_api.dart';
import '../../core/api/control_api.dart';
import '../../core/local/pending_records_store.dart';
import '../control_form/domain/control_context.dart';
import '../control_form/presentation/control_form_page.dart';
import '../control_form/presentation/qr_scanner_page.dart';
import '../calidad_faret/presentation/calidad_faret_form_page.dart';
import '../calidad_faret/presentation/calidad_faret_pallet_form_page.dart';
import '../producto_terminado/presentation/producto_terminado_form_page.dart';
import '../../core/api/calidad_faret_operadores_api.dart';
import '../../core/local/cached_users_store.dart';
import '../../core/local/offline_catalog_store.dart';
import '../../core/network/network_mode_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _bootstrapHome() async {
    await _initializeOfflineCatalog();
    await _downloadOfflineCatalog();

    await _loadOperators();
    await _loadFaretOperadores();
    await _loadPendingCount();
  }

  String? _selectedArea;
  Map<String, dynamic>? _selectedOperator;
  bool _loadingOperators = true;
  String _faretOperadorText = '';
  List<String> _faretOperadores = [];

  final List<String> _areas = [
    'CALIDAD INNPACK',
    'PRODUCCION INNPACK',
    'CALIDAD/PRODUCCION FARET',
    'CONTROL PALLET / PAPEL FARET',
    'PRODUCTO TERMINADO',
  ];

  bool get _isCalidadFaret => _selectedArea == 'CALIDAD/PRODUCCION FARET';
  bool get _isControlPalletPapelFaret =>
      _selectedArea == 'CONTROL PALLET / PAPEL FARET';
  bool get _isProductoTerminado => _selectedArea == 'PRODUCTO TERMINADO';
  final CatalogosApi _catalogosApi = CatalogosApi();
  final CalidadFaretOperadoresApi _calidadFaretOperadoresApi =
      CalidadFaretOperadoresApi();
  final ControlApi _controlApi = ControlApi();
  final PendingRecordsStore _pendingRecordsStore = PendingRecordsStore();
  final CachedUsersStore _cachedUsersStore = CachedUsersStore();
  final OfflineCatalogStore _offlineCatalogStore = OfflineCatalogStore();
  final NetworkModeService _networkModeService = NetworkModeService();
  List<Map<String, dynamic>> _operators = [];
  int _pendingCount = 0;
  bool _syncingPendingRecords = false;

  @override
  void initState() {
    super.initState();

    _bootstrapHome();
  }

  Future<void> _initializeOfflineCatalog() async {
    await _offlineCatalogStore.ensureSeedCatalogLoaded();
  }

  Future<void> _loadOperators() async {
    try {
      final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

      if (shouldUseOffline) {
        throw Exception('Modo offline');
      }

      final users = await _catalogosApi.obtenerUsuarios();

      await _cachedUsersStore.saveUsers(users);

      if (!mounted) return;

      setState(() {
        _operators = users;
        _loadingOperators = false;
      });
    } catch (error) {
      final cachedUsers = await _cachedUsersStore.getUsers();

      final offlineUsers = cachedUsers.isNotEmpty
          ? cachedUsers
          : List<Map<String, dynamic>>.from(
              await _offlineCatalogStore.getUsuarios(),
            );

      if (!mounted) return;

      setState(() {
        _operators = offlineUsers;
        _loadingOperators = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offlineUsers.isEmpty
                ? 'Sin conexión y sin operadores guardados'
                : 'Operadores cargados sin conexión',
          ),
        ),
      );
    }
  }

  Future<void> _loadFaretOperadores() async {
    try {
      final operadores = await _calidadFaretOperadoresApi.obtenerOperadores();

      if (!mounted) return;

      setState(() {
        _faretOperadores = operadores;
      });
    } catch (_) {
      // Sugerencias no disponibles; el campo sigue siendo texto libre.
    }
  }

  Future<void> _downloadOfflineCatalog({bool force = false}) async {
    try {
      final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

      if (shouldUseOffline && !force) {
        debugPrint('Catálogo offline: usando catálogo local');
        return;
      }

      await _controlApi.descargarCatalogoOffline();

      debugPrint('Catálogo offline actualizado desde backend');
    } catch (error) {
      debugPrint(
        'No se pudo actualizar catálogo offline: $error',
      );
    }
  }

  Future<Map<String, dynamic>?> _findOfflineQrContext(
    String codigoQr,
  ) async {
    final qrContexts = await _offlineCatalogStore.getQrContexts();

    try {
      final item = qrContexts.firstWhere(
        (item) =>
            item['codigoQr'].toString().trim().toUpperCase() ==
            codigoQr.trim().toUpperCase(),
      );

      return Map<String, dynamic>.from(item as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPendingCount() async {
    final count = await _pendingRecordsStore.countPendingRecords();

    if (!mounted) return;

    setState(() {
      _pendingCount = count;
    });
  }

  Future<void> _syncPendingRecords() async {
    if (_syncingPendingRecords) return;

    final records = await _pendingRecordsStore.getPendingRecords();

    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros pendientes')),
      );
      return;
    }

    setState(() {
      _syncingPendingRecords = true;
    });

    int syncedCount = 0;

    try {
      for (final record in records) {
        final payload = Map<String, dynamic>.from(record['payload']);

        await _controlApi.guardarRegistro(payload);
        await _pendingRecordsStore.removePendingRecord(
          record['localId'].toString(),
        );

        syncedCount++;
      }

      await _loadPendingCount();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registros sincronizados: $syncedCount'),
        ),
      );
    } catch (error) {
      await _loadPendingCount();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No se pudo sincronizar. Pendientes restantes: $_pendingCount'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncingPendingRecords = false;
        });
      }
    }
  }

  Future<void> _openCalidadFaret(BuildContext context) async {
    final operador = _faretOperadorText.trim();

    if (operador.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe ingresar el operador')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalidadFaretFormPage(operador: operador),
      ),
    );

    await _loadFaretOperadores();
  }

  Future<void> _openControlPalletPapelFaret(BuildContext context) async {
    final operador = _faretOperadorText.trim();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalidadFaretPalletFormPage(
          operador: operador.isEmpty ? null : operador,
        ),
      ),
    );

    await _loadFaretOperadores();
  }

  Future<void> _openProductoTerminado(BuildContext context) async {
    if (_selectedOperator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar operador')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductoTerminadoFormPage(
          usuarioId: _selectedOperator!['id'] as int,
          usuarioNombre: _selectedOperator!['nombre_completo'].toString(),
        ),
      ),
    );
  }

  Future<void> _startQrScanner(BuildContext context) async {
    if (_selectedArea == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar área')),
      );
      return;
    }

    if (_selectedOperator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar operador')),
      );
      return;
    }

    try {
      final qrCode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const QrScannerPage(),
        ),
      );

      if (qrCode == null || qrCode.trim().isEmpty) {
        return;
      }
      Map<String, dynamic>? qrContext;

      final cleanQrCode = qrCode.trim();
      final shouldUseOffline = await _networkModeService.shouldUseOfflineMode();

      if (shouldUseOffline) {
        qrContext = await _findOfflineQrContext(cleanQrCode);

        if (qrContext != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR cargado sin conexión'),
            ),
          );
        }
      } else {
        try {
          qrContext = await _controlApi.obtenerContextoPorQr(cleanQrCode);
        } catch (_) {
          qrContext = await _findOfflineQrContext(cleanQrCode);

          if (qrContext != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('QR cargado sin conexión'),
              ),
            );
          }
        }
      }

      if (qrContext == null) {
        throw Exception(
          'QR no encontrado online nix offline',
        );
      }
      debugPrint('QR DEBUG machine: ${qrContext['machineName']}');
      debugPrint(
          'QR DEBUG tiposOnda: ${(qrContext['tiposOnda'] as List?)?.length}');
      debugPrint(
          'QR DEBUG materiales: ${(qrContext['materiales'] as List?)?.length}');
      debugPrint(
          'QR DEBUG ensayos: ${(qrContext['ensayosLaboratorio'] as List?)?.length}');
      final controlContext = ControlContext(
        machineId: qrContext['machineId'] as int,
        machineName: qrContext['machineName'].toString(),
        processId: qrContext['processId'] as int,
        processName: qrContext['processName'].toString(),
        formId: qrContext['formId'] == null ? null : qrContext['formId'] as int,
        formName: qrContext['formName']?.toString() ?? '',
        userId: _selectedOperator!['id'] as int,
        userName: _selectedOperator!['nombre_completo'].toString(),
        operatorArea: _selectedArea!,
        parametrosVisuales: List<Map<String, dynamic>>.from(
          qrContext['parametrosVisuales'] ?? [],
        ),
        tiposOnda: List<Map<String, dynamic>>.from(
          qrContext['tiposOnda'] ?? [],
        ),
        materiales: List<Map<String, dynamic>>.from(
          qrContext['materiales'] ?? [],
        ),
        ensayosLaboratorio: List<Map<String, dynamic>>.from(
          qrContext['ensayosLaboratorio'] ?? [],
        ),
        origenesProblema: List<Map<String, dynamic>>.from(
          qrContext['origenesProblema'] ?? [],
        ),
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ControlFormPage(
            controlContext: controlContext,
          ),
        ),
      );

      await _loadPendingCount();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error QR: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF17212B),
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
                Colors.black.withOpacity(0.72),
                Colors.black.withOpacity(0.60),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2A33).withOpacity(0.88),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logo2.png',
                          height: 64,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.verified_outlined,
                              size: 56,
                              color: Color(0xFF607D8B),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Control de Calidad',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Registro operacional de planta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFFB0BEC5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Área',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB0BEC5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedArea,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFFEEF3F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF8FA3AD),
                            ),
                          ),
                        ),
                        items: _areas
                            .map(
                              (area) => DropdownMenuItem(
                                value: area,
                                child: Text(area),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedArea = value;
                          });
                        },
                      ),
                      if (!_isCalidadFaret && !_isControlPalletPapelFaret) ...[
                        const SizedBox(height: 16),
                        Text(
                          _loadingOperators
                              ? 'Cargando operadores...'
                              : 'Operador',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB0BEC5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedOperator,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFEEF3F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0xFF8FA3AD),
                              ),
                            ),
                          ),
                          items: _operators
                              .map(
                                (operator) =>
                                    DropdownMenuItem<Map<String, dynamic>>(
                                  value: operator,
                                  child: Text(
                                    operator['nombre_completo'].toString(),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _loadingOperators
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedOperator = value;
                                  });
                                },
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Operador',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB0BEC5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Autocomplete<String>(
                          initialValue:
                              TextEditingValue(text: _faretOperadorText),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return _faretOperadores;
                            }

                            final query = textEditingValue.text.toLowerCase();

                            return _faretOperadores.where(
                              (operador) =>
                                  operador.toLowerCase().contains(query),
                            );
                          },
                          onSelected: (selection) {
                            setState(() {
                              _faretOperadorText = selection;
                            });
                          },
                          fieldViewBuilder: (
                            context,
                            controller,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFEEF3F5),
                                hintText: 'Escriba o elija un operador',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF8FA3AD),
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                _faretOperadorText = value;
                              },
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          'Registros pendientes: $_pendingCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFCFD8DC),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_isCalidadFaret) {
                              _openCalidadFaret(context);
                            } else if (_isControlPalletPapelFaret) {
                              _openControlPalletPapelFaret(context);
                            } else if (_isProductoTerminado) {
                              _openProductoTerminado(context);
                            } else {
                              _startQrScanner(context);
                            }
                          },
                          icon: Icon(
                            (_isCalidadFaret ||
                                    _isControlPalletPapelFaret ||
                                    _isProductoTerminado)
                                ? Icons.assignment
                                : Icons.qr_code_scanner,
                          ),
                          label: Text(
                            (_isCalidadFaret ||
                                    _isControlPalletPapelFaret ||
                                    _isProductoTerminado)
                                ? 'ABRIR FORMULARIO'
                                : 'ESCANEAR QR',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8BC34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _syncingPendingRecords
                              ? null
                              : () async {
                                  await _downloadOfflineCatalog(force: true);
                                  await _loadOperators();

                                  if (_pendingCount > 0) {
                                    await _syncPendingRecords();
                                  }
                                },
                          icon: _syncingPendingRecords
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            _syncingPendingRecords
                                ? 'SINCRONIZANDO...'
                                : 'SINCRONIZAR DATOS',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF263238),
                            disabledForegroundColor: Colors.white70,
                            disabledBackgroundColor: const Color(0xFF37474F),
                            side: const BorderSide(
                              color: Color(0xFF90A4AE),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
