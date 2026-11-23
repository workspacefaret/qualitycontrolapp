#!/usr/bin/env bash
# Valida la migracion 015 (defectos y controles FARET) contra SQL Server REAL (LocalDB, base aislada calidad_015_test, compat 130)
# con 009+010 aplicadas, la cuenta de la app con permisos minimos y los triggers reales. Nunca toca produccion.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"; MIG="$(cd "$AQUI/.." && pwd)"; RAIZ="$(cd "$MIG/../.." && pwd)"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
DB=calidad_015_test
PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"
[ -z "$PIPE" ] && { sqllocaldb start MSSQLLocalDB >/dev/null; PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"; }
wp() { cygpath -m "$1"; }
q() { sqlcmd -S "$PIPE" -E -b -d "$DB" -h -1 -W "$@"; }
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
val() { local r; r="$(q -Q "SET NOCOUNT ON; $2" 2>&1 | tr -d '\r' | head -1)"; [ "$r" = "$3" ] && ok "$1 (= $3)" || ko "$1: esperado '$3', obtenido '$r'"; }
falla() { local out; out="$(q -Q "SET NOCOUNT ON; $2" 2>&1)"; echo "$out" | grep -q "$3" && ok "$1 (error $3 como se esperaba)" || ko "$1: no falló con $3 -> $(echo "$out" | head -2)"; }


sqlcmd -S "$PIPE" -E -b -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END; CREATE DATABASE $DB COLLATE Latin1_General_100_CI_AI_SC; ALTER DATABASE $DB SET COMPATIBILITY_LEVEL = 130" || exit 2
sqlcmd -S "$PIPE" -E -d "$DB" -i "$(wp "$DDL")" >/dev/null 2>&1 || { echo "DDL no cargó"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/009_client_uuid_idempotencia.sql")" >/dev/null 2>&1 || { echo "009 no aplicó"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$AQUI/010_t_setup.sql")" >/dev/null 2>&1 || { echo "setup falló"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/010_catalogo_eventos_calidad_faret.sql")" >/dev/null 2>&1 || { echo "010 no aplicó"; exit 2; }
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_admin_defectos_faret.sql")" >/dev/null 2>&1 && ok "015 aplica" || ko "015 no aplicó"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_admin_defectos_faret.sql")" >/dev/null 2>&1 && ok "015 es idempotente (2.ª ejecución)" || ko "015 no es idempotente"
val "defectos existentes quedan compartidos (empresa NULL)" "SELECT COUNT(*) FROM dbo.parametros_control_visual WHERE empresa IS NOT NULL" "0"
falla "CHECK: empresa solo NULL o FARET" "INSERT INTO dbo.parametros_control_visual (proceso_id, nombre, criticidad, activo, empresa) VALUES (4, N'x', N'mayor', 1, N'OTRA')" "547"

# --- Producto Terminado: defecto propio de FARET ---
q -Q "SET IDENTITY_INSERT dbo.procesos ON; INSERT INTO dbo.procesos (id, nombre, activo) VALUES (4, N'Pegado', 1); SET IDENTITY_INSERT dbo.procesos OFF" >/dev/null 2>&1
q -Q "INSERT INTO dbo.parametros_control_visual (proceso_id, nombre, criticidad, activo) VALUES (4, N'COMPARTIDO PEGADO', N'mayor', 1)" >/dev/null 2>&1
val "app: INSERT de defecto propio FARET (permiso mínimo)" "EXECUTE AS USER = N'quality_control_backend_sql'; INSERT INTO dbo.parametros_control_visual (proceso_id, nombre, criticidad, activo, empresa) OUTPUT INSERTED.nombre VALUES (4, N'MEZCLA DE PRODUCTO', N'critico', 1, N'FARET'); REVERT" "MEZCLA DE PRODUCTO"
val "app: UPDATE de nombre/criticidad/activo" "EXECUTE AS USER = N'quality_control_backend_sql'; UPDATE dbo.parametros_control_visual SET nombre = N'MEZCLA DE PRODUCTO 2', criticidad = N'mayor', activo = 1 WHERE empresa = N'FARET'; REVERT; SELECT nombre FROM dbo.parametros_control_visual WHERE empresa = N'FARET'" "MEZCLA DE PRODUCTO 2"
falla "app: NO puede cambiar empresa/proceso (UPDATE por columna)" "EXECUTE AS USER = N'quality_control_backend_sql'; UPDATE dbo.parametros_control_visual SET empresa = NULL WHERE empresa = N'FARET'; REVERT" "230"
falla "app: NO puede borrar defectos" "EXECUTE AS USER = N'quality_control_backend_sql'; DELETE FROM dbo.parametros_control_visual WHERE empresa = N'FARET'; REVERT" "229"
val "INNPACK (empresa IS NULL) NO ve el defecto FARET" "SELECT COUNT(*) FROM dbo.parametros_control_visual WHERE activo = 1 AND proceso_id = 4 AND empresa IS NULL" "1"
val "FARET ve compartido + propio" "SELECT COUNT(*) FROM dbo.parametros_control_visual WHERE activo = 1 AND proceso_id = 4 AND (empresa IS NULL OR empresa = N'FARET')" "2"

# --- Calidad/Producción: defecto nuevo con triggers y bitácora reales ---
val "app: INSERT de un evento nuevo" "EXECUTE AS USER = N'quality_control_backend_sql'; INSERT INTO dbo.calidad_faret_eventos (id_evento, cod_area, tipo_registro, defecto, criticidad, estado, orden, defecto_origen, criticidad_origen, estado_origen, texto_documento) OUTPUT INSERTED.id_evento VALUES (N'OFF-900', N'OFF', N'Desviación', N'MEZCLA DE PRODUCTO', N'Mayor', N'Activo', 99, N'MEZCLA DE PRODUCTO', N'Mayor', N'Activo', N'Mayor: MEZCLA DE PRODUCTO'); REVERT" "OFF-900"
val "el evento nuevo es operable (vista)" "SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento = N'OFF-900'" "1"
falla "UQ: mismo defecto en la misma área" "INSERT INTO dbo.calidad_faret_eventos (id_evento, cod_area, tipo_registro, defecto, criticidad, estado, orden, defecto_origen, criticidad_origen, estado_origen, texto_documento) VALUES (N'OFF-901', N'OFF', N'Desviación', N'mezcla de producto', N'Mayor', N'Activo', 100, N'x', N'Mayor', N'Activo', N'x')" "2627"
q -Q "EXECUTE AS USER = N'quality_control_backend_sql'; EXEC sp_set_session_context N'usuario', N'Tito TI'; EXEC sp_set_session_context N'motivo', N'Administración de planta (QCC)'; UPDATE dbo.calidad_faret_eventos SET criticidad = N'Critico', orden = 5, defecto = N'MEZCLA DE PRODUCTOS' WHERE id_evento = N'OFF-900'; EXEC sp_set_session_context N'usuario', NULL; EXEC sp_set_session_context N'motivo', NULL; REVERT" >/dev/null 2>&1 && ok "app: UPDATE de criticidad/orden/defecto con contexto de auditoría" || ko "app: UPDATE de evento"
val "la bitácora del trigger registró 3 campos con el usuario del panel" "SELECT CAST(COUNT(*) AS NVARCHAR(5)) + N'/' + MIN(usuario) FROM dbo.calidad_faret_catalogo_auditoria WHERE clave = N'OFF-900' AND accion = N'MODIFICACION'" "3/Tito TI"
val "el *_origen del defecto nuevo no cambió" "SELECT defecto_origen + N'|' + criticidad_origen FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-900'" "MEZCLA DE PRODUCTO|Mayor"
falla "cod_area de un evento no se puede reasignar (CHECK ID/área)" "UPDATE dbo.calidad_faret_eventos SET cod_area = N'SER' WHERE id_evento = N'OFF-900'" "547"
falla "app: NO puede modificar el origen (UPDATE por columna)" "EXECUTE AS USER = N'quality_control_backend_sql'; UPDATE dbo.calidad_faret_eventos SET defecto_origen = N'x' WHERE id_evento = N'OFF-900'; REVERT" "230"
falla "trigger: los eventos no se borran" "DELETE FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-900'" "51"
falla "un evento pendiente de aprobación no se activa sin Calidad (CK)" "UPDATE dbo.calidad_faret_eventos SET estado = N'Activo' WHERE id_evento = N'SER-007'" "547"
val "la baja lógica deja de ser operable" "UPDATE dbo.calidad_faret_eventos SET estado = N'Inactivo' WHERE id_evento = N'OFF-900'; SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento = N'OFF-900'" "0"

# --- Pallet/Papel: preguntas ---
q -Q "INSERT INTO dbo.calidad_faret_pallet_preguntas (texto, orden, activo) VALUES (N'Base', 1, 1)" >/dev/null 2>&1
val "app: INSERT de pregunta nueva" "EXECUTE AS USER = N'quality_control_backend_sql'; INSERT INTO dbo.calidad_faret_pallet_preguntas (texto, orden, activo) OUTPUT INSERTED.orden VALUES (N'Nueva', 50, 1); REVERT" "50"
val "app: UPDATE de texto/orden/activo" "EXECUTE AS USER = N'quality_control_backend_sql'; UPDATE dbo.calidad_faret_pallet_preguntas SET texto = N'Editada', orden = 51, activo = 0 WHERE texto = N'Nueva'; REVERT; SELECT texto FROM dbo.calidad_faret_pallet_preguntas WHERE orden = 51" "Editada"
falla "app: NO puede borrar preguntas" "EXECUTE AS USER = N'quality_control_backend_sql'; DELETE FROM dbo.calidad_faret_pallet_preguntas WHERE texto = N'Base'; REVERT" "229"
val "created_at se llena solo (base de la tolerancia de preguntas nuevas)" "SELECT COUNT(*) FROM dbo.calidad_faret_pallet_preguntas WHERE created_at IS NULL" "0"

# --- Rollback ---
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_admin_defectos_faret_rollback.sql")" >/dev/null 2>&1 && ok "rollback ejecuta" || ko "rollback falló"
val "rollback con defectos FARET conserva la columna (protege datos)" "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.parametros_control_visual') AND name = N'empresa'" "1"
falla "tras rollback la app ya no inserta defectos" "EXECUTE AS USER = N'quality_control_backend_sql'; INSERT INTO dbo.parametros_control_visual (proceso_id, nombre, criticidad, activo) VALUES (4, N'zz', N'mayor', 1); REVERT" "229"
q -Q "DELETE FROM dbo.parametros_control_visual WHERE empresa = N'FARET'" >/dev/null 2>&1
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_admin_defectos_faret_rollback.sql")" >/dev/null 2>&1
val "rollback sin defectos FARET elimina la columna" "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.parametros_control_visual') AND name = N'empresa'" "0"

echo; echo "RESULTADO 015 (LocalDB, compat 130): PASS=$PASS FAIL=$FAIL"
sqlcmd -S "$PIPE" -E -Q "ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB" >/dev/null 2>&1
[ $FAIL -eq 0 ]
