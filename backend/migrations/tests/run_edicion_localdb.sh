#!/usr/bin/env bash
# Valida la migración 011 (bitácora + permisos de edición) y las sentencias SQL de la edición contra SQL Server REAL (LocalDB,
# base aislada calidad_ed_test, compatibilidad 130 = SQL Server 2016), con la cuenta mínima de la app (EXECUTE AS USER).
# Nunca se conecta a producción: solo a la instancia LocalDB de esta máquina.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"; MIG="$(cd "$AQUI/.." && pwd)"; RAIZ="$(cd "$MIG/../.." && pwd)"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
DB=calidad_ed_test
PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"
[ -z "$PIPE" ] && { sqllocaldb start MSSQLLocalDB >/dev/null; PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"; }
wp() { cygpath -m "$1"; }
q() { sqlcmd -S "$PIPE" -E -b -d "$DB" -h -1 -W "$@"; }
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
val() { local r; r="$(q -Q "SET NOCOUNT ON; $2" 2>&1 | tr -d '\r' | head -1)"; [ "$r" = "$3" ] && ok "$1 (= $3)" || ko "$1: esperado '$3', obtenido '$r'"; }
falla() { local out; out="$(q -Q "SET NOCOUNT ON; $2" 2>&1)"; echo "$out" | grep -q "$3" && ok "$1 (error $3 como se esperaba)" || ko "$1: no falló con $3 -> $(echo "$out" | head -2)"; }
exito() { q -Q "SET NOCOUNT ON; $2" >/dev/null 2>&1 && ok "$1" || ko "$1 -> $(q -Q "SET NOCOUNT ON; $2" 2>&1 | head -2)"; }
APP="EXECUTE AS USER = N'quality_control_backend_sql';"

sqlcmd -S "$PIPE" -E -b -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END; CREATE DATABASE $DB COLLATE Latin1_General_100_CI_AI_SC; ALTER DATABASE $DB SET COMPATIBILITY_LEVEL = 130" || exit 2
sqlcmd -S "$PIPE" -E -d "$DB" -i "$(wp "$DDL")" >/dev/null 2>&1 || { echo "DDL no cargó"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/009_client_uuid_idempotencia.sql")" >/dev/null 2>&1 || { echo "009 no aplicó"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$AQUI/010_t_setup.sql")" >/dev/null 2>&1 || { echo "setup falló"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/010_catalogo_eventos_calidad_faret.sql")" >/dev/null 2>&1 || { echo "010 no aplicó"; exit 2; }

# Datos: un registro de Calidad con evento + histórico, un registro Pallet con 2 respuestas
q -Q "INSERT INTO registros_calidad_faret (nv_faret, nv_vb_aprobado, area_control, operador, maquina, presenta_defectos, area_defecto, fecha_registro, hora_registro) VALUES (N'NV-T1', 1, N'03-OFFSET', N'X', N'KBA 2', 1, N'03-OFFSET', CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))" >/dev/null 2>&1
REG="$(q -Q "SET NOCOUNT ON; SELECT MAX(id) FROM registros_calidad_faret" | tr -d '\r' | head -1)"
q -Q "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto) VALUES ($REG, N'DEFECTO HISTORICO')" >/dev/null 2>&1
q -Q "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'DIFERENCIA DE TONO', N'OFF-001', (SELECT criticidad FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-001'))" >/dev/null 2>&1
q -Q "IF NOT EXISTS (SELECT 1 FROM calidad_faret_pallet_preguntas) INSERT INTO calidad_faret_pallet_preguntas (texto, orden, activo) VALUES (N'Pallet limpio', 1, 1), (N'Sin humedad', 2, 1)" >/dev/null 2>&1
q -Q "INSERT INTO registros_calidad_faret_pallet (tipo_material, dimension, numero_pallet, fecha_registro, hora_registro) VALUES (N'NV', N'100x70', N'P-1', CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))" >/dev/null 2>&1
PAL="$(q -Q "SET NOCOUNT ON; SELECT MAX(id) FROM registros_calidad_faret_pallet" | tr -d '\r' | head -1)"
q -Q "INSERT INTO registro_calidad_faret_pallet_respuestas (registro_id, pregunta_id, resultado, observacion) SELECT $PAL, id, N'CUMPLE', NULL FROM calidad_faret_pallet_preguntas" >/dev/null 2>&1
HIST_ANTES="$(q -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM registros_calidad_faret" | tr -d '\r' | head -1)"

# --- Antes de la 011 la cuenta de la app NO puede editar ---
falla "antes de la 011: la app no puede borrar defectos" "$APP DELETE FROM registro_calidad_faret_defectos WHERE registro_id = $REG; REVERT" "229"
falla "antes de la 011: la app no puede editar observaciones" "$APP UPDATE registros_calidad_faret SET observaciones = N'x' WHERE id = $REG; REVERT" "230"

# --- Aplicar 011 (dos veces: idempotente) ---
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/011_edicion_inspecciones_faret.sql")" >/dev/null 2>&1 && ok "011 aplica" || ko "011 aplica"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/011_edicion_inspecciones_faret.sql")" >/dev/null 2>&1 && ok "011 es idempotente (2.ª ejecución sin error)" || ko "011 idempotente"
val "bitácora creada" "SELECT COUNT(*) FROM sys.tables WHERE name = N'inspecciones_faret_auditoria'" "1"
val "histórico intacto: mismo número de registros" "SELECT COUNT(*) FROM registros_calidad_faret" "$HIST_ANTES"

# --- Sentencias de edición con la cuenta mínima de la app ---
exito "app: SELECT ... WITH (UPDLOCK, ROWLOCK) del registro (lectura previa de la edición)" "$APP BEGIN TRAN; SELECT nv_faret FROM registros_calidad_faret WITH (UPDLOCK, ROWLOCK) WHERE id = $REG AND eliminado = 0; ROLLBACK; REVERT"
val "app: UPDATE de campos editables (misma sentencia del backend)" "$APP UPDATE registros_calidad_faret SET nv_faret = N'NV-EDIT', nv_vb_aprobado = 1, n_pliego = NULL, n_pasada = NULL, n_item = NULL, pliego_control_n = NULL, observaciones = N'corregida ñ á', area_control = N'03-OFFSET', operador = N'X', operador_otro = NULL, maquina = N'KBA 3', presenta_defectos = 1, area_defecto = N'03-OFFSET', tipo_folia = NULL, accion_correctiva = NULL WHERE id = $REG AND eliminado = 0; SELECT nv_faret FROM registros_calidad_faret WHERE id = $REG; REVERT" "NV-EDIT"
falla "app: NO puede editar fecha_registro" "$APP UPDATE registros_calidad_faret SET fecha_registro = '2020-01-01' WHERE id = $REG; REVERT" "230"
falla "app: NO puede editar operador_registro" "$APP UPDATE registros_calidad_faret SET operador_registro = N'otro' WHERE id = $REG; REVERT" "230"
falla "app: NO puede editar client_uuid" "$APP UPDATE registros_calidad_faret SET client_uuid = N'x' WHERE id = $REG; REVERT" "230"
val "app: borrado lógico (eliminado) sigue funcionando" "$APP UPDATE registros_calidad_faret SET eliminado = 0 WHERE id = $REG; SELECT 1; REVERT" "1"
val "app: DELETE del defecto quitado (por defecto + id_evento)" "$APP DECLARE @id INT = $REG, @defecto NVARCHAR(150) = N'DIFERENCIA DE TONO', @idEvento NVARCHAR(10) = N'OFF-001'; DELETE FROM registro_calidad_faret_defectos WHERE registro_id = @id AND defecto = @defecto AND ((@idEvento IS NULL AND id_evento IS NULL) OR id_evento = @idEvento); SELECT COUNT(*) FROM registro_calidad_faret_defectos WHERE registro_id = @id; REVERT" "1"
val "el defecto histórico (sin id_evento/criticidad) se conservó" "SELECT COUNT(*) FROM registro_calidad_faret_defectos WHERE registro_id = $REG AND id_evento IS NULL AND criticidad IS NULL" "1"
val "app: INSERT de un evento nuevo con criticidad del catálogo" "$APP INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'MANCHA', N'OFF-002', (SELECT criticidad FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-002')); SELECT COUNT(*) FROM registro_calidad_faret_defectos WHERE registro_id = $REG AND id_evento = N'OFF-002'; REVERT" "1"
falla "trigger: un evento de otra área sigue rechazado al editar" "$APP INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'x', N'TRO-001', N'Critico'); REVERT" "51031"

# Pallet
val "app: UPDATE de cabecera Pallet" "$APP UPDATE registros_calidad_faret_pallet SET tipo_material = N'NV', dimension = N'120x80', fibra = NULL, numero_pallet = N'P-1', numero_pasadas_prensa = 2, observaciones = NULL, area_control = NULL, operador = NULL, operador_otro = NULL, maquina = NULL WHERE id = $PAL AND eliminado = 0; SELECT dimension FROM registros_calidad_faret_pallet WHERE id = $PAL; REVERT" "120x80"
val "app: UPDATE de respuesta del checklist" "$APP UPDATE registro_calidad_faret_pallet_respuestas SET resultado = N'NO_CUMPLE', observacion = N'Húmedo' WHERE registro_id = $PAL AND pregunta_id = (SELECT MIN(id) FROM calidad_faret_pallet_preguntas); SELECT COUNT(*) FROM registro_calidad_faret_pallet_respuestas WHERE registro_id = $PAL AND resultado = N'NO_CUMPLE'; REVERT" "1"
falla "app: NO puede cambiar a qué pregunta/registro pertenece una respuesta" "$APP UPDATE registro_calidad_faret_pallet_respuestas SET pregunta_id = 999 WHERE registro_id = $PAL; REVERT" "230"
falla "app: NO puede editar fecha del registro Pallet" "$APP UPDATE registros_calidad_faret_pallet SET fecha_registro = '2020-01-01' WHERE id = $PAL; REVERT" "230"
falla "app: CHECK de tipo_material" "$APP UPDATE registros_calidad_faret_pallet SET tipo_material = N'ZZ' WHERE id = $PAL; REVERT" "547"

# Bitácora
AUD="INSERT INTO dbo.inspecciones_faret_auditoria (tipo, registro_id, campo, valor_anterior, valor_nuevo, motivo, usuario_id, usuario_nombre, origen) VALUES (N'CALIDAD', $REG, N'Máquina', N'KBA 2', N'KBA 3', N'Error de digitación', N'7', N'Ines Inspectora', N'faret')"
val "app: INSERT en la bitácora" "$APP $AUD; SELECT COUNT(*) FROM dbo.inspecciones_faret_auditoria; REVERT" "1"
val "la fecha de la bitácora la pone SQL Server" "SELECT CASE WHEN fecha >= DATEADD(MINUTE, -5, SYSDATETIME()) THEN 1 ELSE 0 END FROM dbo.inspecciones_faret_auditoria" "1"
val "la bitácora guarda acentos y usuario" "SELECT usuario_nombre + N'|' + campo FROM dbo.inspecciones_faret_auditoria" "Ines Inspectora|Máquina"
val "app: SELECT de la bitácora (consulta de historial)" "$APP SELECT COUNT(*) FROM dbo.inspecciones_faret_auditoria WHERE tipo = N'CALIDAD' AND registro_id = $REG; REVERT" "1"
falla "app: la bitácora NO se puede modificar" "$APP UPDATE dbo.inspecciones_faret_auditoria SET motivo = N'x'; REVERT" "229"
falla "app: la bitácora NO se puede borrar" "$APP DELETE FROM dbo.inspecciones_faret_auditoria; REVERT" "229"
falla "ni siquiera con cuenta propietaria: UPDATE bloqueado por trigger" "UPDATE dbo.inspecciones_faret_auditoria SET motivo = N'x'" "51110"
falla "ni siquiera con cuenta propietaria: DELETE bloqueado por trigger" "DELETE FROM dbo.inspecciones_faret_auditoria" "51110"
falla "tipo de bitácora inválido (CHECK)" "INSERT INTO dbo.inspecciones_faret_auditoria (tipo, registro_id, campo, motivo) VALUES (N'OTRO', 1, N'x', N'y')" "547"

# Resumen de ediciones para el listado (misma subconsulta que resumenEdicionSql)
val "resumen de ediciones (cantidad)" "SELECT (SELECT COUNT(DISTINCT au.fecha) FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'CALIDAD' AND au.registro_id = r.id) FROM registros_calidad_faret r WHERE r.id = $REG" "1"
val "resumen de ediciones (último usuario)" "SELECT (SELECT TOP 1 au.usuario_nombre FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'CALIDAD' AND au.registro_id = r.id ORDER BY au.id DESC) FROM registros_calidad_faret r WHERE r.id = $REG" "Ines Inspectora"
val "registro sin ediciones: cantidad 0 (histórico intacto)" "SELECT (SELECT COUNT(DISTINCT au.fecha) FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'PALLET' AND au.registro_id = $PAL)" "0"

# Rollback y reaplicación
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/011_edicion_inspecciones_faret_rollback.sql")" >/dev/null 2>&1 && ok "rollback de la 011 aplica" || ko "rollback 011"
val "tras el rollback no existe la bitácora" "SELECT COUNT(*) FROM sys.tables WHERE name = N'inspecciones_faret_auditoria'" "0"
falla "tras el rollback la app vuelve a no poder editar" "$APP UPDATE registros_calidad_faret SET observaciones = N'x' WHERE id = $REG; REVERT" "230"
val "tras el rollback el borrado lógico sigue permitido" "$APP UPDATE registros_calidad_faret SET eliminado = 0 WHERE id = $REG; SELECT 1; REVERT" "1"
val "tras el rollback los datos siguen intactos" "SELECT COUNT(*) FROM registros_calidad_faret" "$HIST_ANTES"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/011_edicion_inspecciones_faret.sql")" >/dev/null 2>&1 && ok "011 se puede reaplicar tras el rollback" || ko "reaplicar 011"

echo; echo "RESULTADO EDICION-SQL (LocalDB, compat 130): PASS=$PASS FAIL=$FAIL"
sqlcmd -S "$PIPE" -E -Q "ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB" >/dev/null 2>&1
[ $FAIL -eq 0 ]
