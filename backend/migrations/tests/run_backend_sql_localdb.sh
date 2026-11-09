#!/usr/bin/env bash
# Valida contra SQL Server REAL (LocalDB, base aislada calidad_be_test, compatibilidad 130 = SQL Server 2016) las MISMAS sentencias
# SQL que usa el backend (backend/src/utils/eventosCalidadFaret.js y calidadFaret.controller.js), con la 010 aplicada y el
# esquema/triggers reales. Nunca se conecta a producción: solo a la instancia LocalDB de esta máquina.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"; MIG="$(cd "$AQUI/.." && pwd)"; RAIZ="$(cd "$MIG/../.." && pwd)"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
DB=calidad_be_test
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
val "compatibilidad 130 (SQL Server 2016)" "SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()" "130"

# Sentencias exactas del backend
SQLS="$(cd "$RAIZ/backend" && node -e "const u=require('./src/utils/eventosCalidadFaret');console.log(JSON.stringify({a:u.SQL_AREAS,e:u.SQL_EVENTOS}))")"
SQL_A="$(echo "$SQLS" | python -I -c "import sys,json;print(json.load(sys.stdin)['a'])")"
SQL_E="$(echo "$SQLS" | python -I -c "import sys,json;print(json.load(sys.stdin)['e'])")"
SQL_A0="${SQL_A%% ORDER BY*}"; SQL_E0="${SQL_E%% ORDER BY*}"   # sin ORDER BY para poder envolverlas en un COUNT
q -Q "$SQL_A" >/dev/null 2>&1 && q -Q "$SQL_E" >/dev/null 2>&1 && ok "ambas consultas del backend (con ORDER BY) se ejecutan en SQL 2016" || ko "consultas del backend"
val "SQL_AREAS del backend: 8 áreas activas" "SELECT COUNT(*) FROM ($SQL_A0) t" "8"
val "SQL_EVENTOS del backend: 52 operables" "SELECT COUNT(*) FROM ($SQL_E0) t" "52"
val "los 5 pendientes no están en la consulta del catálogo" "SELECT COUNT(*) FROM ($SQL_E0) t WHERE id_evento IN (N'SER-007', N'FOL-007', N'PEG-007', N'PEG-008', N'CYD-003')" "0"
val "operables por criticidad 38/13/1" "SELECT CAST(SUM(CASE WHEN criticidad=N'Critico' THEN 1 ELSE 0 END) AS NVARCHAR(5)) + N'/' + CAST(SUM(CASE WHEN criticidad=N'Mayor' THEN 1 ELSE 0 END) AS NVARCHAR(5)) + N'/' + CAST(SUM(CASE WHEN criticidad=N'Menor' THEN 1 ELSE 0 END) AS NVARCHAR(5)) FROM ($SQL_E0) t" "38/13/1"
val "resolución (IN) encuentra OFF-001" "DECLARE @e0 NVARCHAR(10) = N'OFF-001'; SELECT area_control FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento IN (@e0)" "03-OFFSET"
val "resolución (IN) no encuentra un pendiente (PEG-008)" "DECLARE @e0 NVARCHAR(10) = N'PEG-008'; SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento IN (@e0)" "0"

# INSERT exacto del controlador (con id_evento) y legado (2 columnas), con los triggers reales
q -Q "INSERT INTO registros_calidad_faret (nv_faret, nv_vb_aprobado, area_control, operador, maquina, presenta_defectos, area_defecto, fecha_registro, hora_registro) VALUES (N'NV-T1', 1, N'03-OFFSET', N'X', N'KBA 2', 1, N'03-OFFSET', CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))" >/dev/null 2>&1
REG="$(q -Q "SET NOCOUNT ON; SELECT MAX(id) FROM registros_calidad_faret" | tr -d '\r' | head -1)"
q -Q "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto) VALUES ($REG, N'DIFERENCIA DE TONO')" >/dev/null 2>&1 && ok "INSERT legado (2 columnas) funciona con la 010 aplicada" || ko "INSERT legado"
q -Q "DECLARE @registroId INT = $REG, @defecto NVARCHAR(150) = N'x', @idEvento NVARCHAR(10) = N'OFF-001', @criticidad NVARCHAR(10) = (SELECT criticidad FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-001'); INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES (@registroId, @defecto, @idEvento, @criticidad)" >/dev/null 2>&1 && ok "INSERT con id_evento + criticidad del catálogo" || ko "INSERT con id_evento"
falla "trigger: evento de otra área" "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'x', N'TRO-001', N'Critico')" "51031"
falla "trigger: evento pendiente no operable" "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'x', N'SER-007', N'Mayor')" "51030"
falla "trigger: evento inexistente" "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'x', N'OFF-999', N'Critico')" "547"
falla "id_evento sin criticidad (CHECK)" "INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento) VALUES ($REG, N'x', N'OFF-001')" "547"
val "el rechazo no dejó filas a medias (2 defectos del registro)" "SELECT COUNT(*) FROM registro_calidad_faret_defectos WHERE registro_id = $REG" "2"

# Permisos reales de la cuenta de la app: lo que el backend lee y escribe
val "app: SELECT en la vista" "EXECUTE AS USER = N'quality_control_backend_sql'; SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables; REVERT" "52"
val "app: SELECT en áreas" "EXECUTE AS USER = N'quality_control_backend_sql'; SELECT COUNT(*) FROM dbo.calidad_faret_areas; REVERT" "8"
falla "app: SIN acceso a la auditoría" "EXECUTE AS USER = N'quality_control_backend_sql'; SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria; REVERT" "229"
falla "app: NO puede modificar el catálogo" "EXECUTE AS USER = N'quality_control_backend_sql'; UPDATE dbo.calidad_faret_eventos SET criticidad = N'Menor' WHERE id_evento = N'OFF-001'; REVERT" "229"
val "app: SÍ puede insertar defectos con id_evento (permiso de tabla existente)" "EXECUTE AS USER = N'quality_control_backend_sql'; INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES ($REG, N'y', N'OFF-002', (SELECT criticidad FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-002')); SELECT COUNT(*) FROM registro_calidad_faret_defectos WHERE registro_id = $REG AND id_evento = N'OFF-002'; REVERT" "1"

echo; echo "RESULTADO BACKEND-SQL (LocalDB, compat 130): PASS=$PASS FAIL=$FAIL"
sqlcmd -S "$PIPE" -E -Q "ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB" >/dev/null 2>&1
[ $FAIL -eq 0 ]
