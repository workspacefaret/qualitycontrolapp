class ControlContext {
  final int machineId;
  final String machineName;

  final int processId;
  final String processName;

  final int? formId;
  final String formName;

  final int userId;
  final String userName;

  final String operatorArea;

  final List<Map<String, dynamic>> parametrosVisuales;
  final List<Map<String, dynamic>> tiposOnda;
  final List<Map<String, dynamic>> materiales;
  final List<Map<String, dynamic>> ensayosLaboratorio;
  final List<Map<String, dynamic>> origenesProblema;

  const ControlContext({
    required this.machineId,
    required this.machineName,
    required this.processId,
    required this.processName,
    required this.formId,
    required this.formName,
    required this.userId,
    required this.userName,
    required this.operatorArea,
    required this.parametrosVisuales,
    this.tiposOnda = const [],
    this.materiales = const [],
    this.ensayosLaboratorio = const [],
    this.origenesProblema = const [],
  });
}
