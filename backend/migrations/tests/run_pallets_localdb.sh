#!/usr/bin/env bash
# Valida la clasificación de pallets contra SQL Server REAL (LocalDB, base aislada pallets_test, compatibilidad 130 = SQL Server 2016):
#   1) migración 015 sobre el esquema real (+008/009 previas): aplica, es idempotente, no altera tablas existentes;
#   2) el CÓDIGO REAL del backend (guardado en la inspección, lecturas, reclasificación, anulación) contra esa base;
#   3) migración pendiente: la inspección se guarda igual aunque las tablas de pallets no existan;
#   4) rollback 015 y re-aplicación.
# Nunca se conecta a producción ni a FPS: solo a la instancia LocalDB de esta máquina.
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"; MIG="$(cd "$AQUI/.." && pwd)"; RAIZ="$(cd "$MIG/../.." && pwd)"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
[ -f "$DDL" ] || DDL="C:/Users/dcarrasco/Desktop/Proyectos/calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql"
export DB=pallets_test
PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"
[ -z "$PIPE" ] && { sqllocaldb start MSSQLLocalDB >/dev/null; PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"; }
export PIPE
wp() { cygpath -m "$1"; }
q() { sqlcmd -S "$PIPE" -E -b -d "$DB" -h -1 -W "$@"; }
PASS=0; FAIL=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
val() { local r; r="$(q -Q "SET NOCOUNT ON; $2" 2>&1 | tr -d '\r' | head -1)"; [ "$r" = "$3" ] && ok "$1 (= $3)" || ko "$1: esperado '$3', obtenido '$r'"; }

nueva_base() {
  sqlcmd -S "$PIPE" -E -b -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END; CREATE DATABASE $DB COLLATE Latin1_General_100_CI_AI_SC; ALTER DATABASE $DB SET COMPATIBILITY_LEVEL = 130" || exit 2
  sqlcmd -S "$PIPE" -E -d "$DB" -i "$(wp "$DDL")" >/dev/null 2>&1 || { echo "DDL no cargó"; exit 2; }
  for m in 008_maquinas_operadores_troquelado_pegado 009_client_uuid_idempotencia; do
    sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/$m.sql")" >/dev/null 2>&1 || { echo "$m no aplicó"; exit 2; }
  done
  # 008 ya crea los inspectores CAL-* (usuario id 1 existe); se siembra lo mínimo para insertar inspecciones.
  q -Q "SET IDENTITY_INSERT procesos ON; INSERT procesos (id, nombre) VALUES (3, N'Troquelado'); SET IDENTITY_INSERT procesos OFF;
        SET IDENTITY_INSERT maquinas ON; INSERT maquinas (id, proceso_id, nombre, codigo_qr) VALUES (6, 3, N'BOBST 142-2', N'MAQ-TRO-TEST'); SET IDENTITY_INSERT maquinas OFF;
        SET IDENTITY_INSERT estados_catalogo ON; INSERT estados_catalogo (id, nombre) VALUES (1, N'Cumple'), (2, N'No Aplica'), (3, N'No Cumple'); SET IDENTITY_INSERT estados_catalogo OFF;
        SET IDENTITY_INSERT parametros_control_visual ON; INSERT parametros_control_visual (id, proceso_id, nombre, criticidad) VALUES (1, 3, N'Descalse', N'mayor'), (2, 3, N'Rayado', N'menor'), (3, 3, N'Aplastado', N'critico'); SET IDENTITY_INSERT parametros_control_visual OFF;" >/dev/null 2>&1 || { echo "semillas fallaron"; exit 2; }
}

echo "== 1) Migración 015: aplicar, idempotencia, no alterar lo existente =="
nueva_base
HASH_ANTES="$(q -Q "SET NOCOUNT ON; SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM registros_control" | tr -d '\r' | head -1)"
COLS_ANTES="$(q -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.columns WHERE object_id IN (OBJECT_ID('registros_control'), OBJECT_ID('parametros_control_visual'), OBJECT_ID('usuarios'))" | tr -d '\r' | head -1)"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets.sql")" >/dev/null 2>&1 && ok "015 aplica sobre el esquema real (SQL Server 2016)" || ko "015 no aplicó"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets.sql")" >/dev/null 2>&1 && ok "015 es idempotente (2.ª ejecución sin error)" || ko "015 no es idempotente"
val "tablas nuevas creadas (2)" "SELECT COUNT(*) FROM sys.tables WHERE name IN (N'pallet_clasificaciones', N'pallet_clasificacion_defectos')" "2"
val "índices creados (3)" "SELECT COUNT(*) FROM sys.indexes WHERE name LIKE N'IX_pallet_clasificaciones_%'" "3"
val "tablas existentes sin cambios de columnas" "SELECT COUNT(*) FROM sys.columns WHERE object_id IN (OBJECT_ID('registros_control'), OBJECT_ID('parametros_control_visual'), OBJECT_ID('usuarios'))" "$COLS_ANTES"
val "registros existentes intactos" "SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM registros_control" "$HASH_ANTES"
val "CHECK de color rechaza valores fuera de AZUL/ROJO/VERDE" "SET XACT_ABORT OFF; BEGIN TRY INSERT registros_control (usuario_id, proceso_id, maquina_id, turno, estado_id, fecha_registro, hora_registro) VALUES (1,3,6,N'A',1,GETDATE(),GETDATE()); INSERT pallet_clasificaciones (registro_id, pallet_codigo, color) VALUES (SCOPE_IDENTITY(), N'1-1', N'AMARILLO'); SELECT N'sin_error'; END TRY BEGIN CATCH SELECT N'rechazado'; END CATCH; DELETE FROM pallet_clasificaciones; DELETE FROM registros_control" "rechazado"

echo "== 2) Código real del backend contra SQL Server real =="
nueva_base
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets.sql")" >/dev/null 2>&1 || { echo "015 no aplicó"; exit 2; }
SALIDA="$(cd "$RAIZ" && node "$(wp "$AQUI/pallets_localdb_harness.js")" completo 2>&1)"
echo "$SALIDA" | grep -E "^(PASS|FAIL|HARNESS)" | while read -r l; do echo "$l"; done
N_OK="$(echo "$SALIDA" | grep -c '^PASS')"; N_KO="$(echo "$SALIDA" | grep -c '^FAIL')"
PASS=$((PASS+N_OK)); FAIL=$((FAIL+N_KO))
echo "$SALIDA" | grep -q '^HARNESS_OK' || { ko "arnés de integración no terminó OK"; echo "$SALIDA" | tail -15; }
val "FK: todas las clasificaciones apuntan a una inspección" "SELECT COUNT(*) FROM pallet_clasificaciones c LEFT JOIN registros_control r ON r.id = c.registro_id WHERE r.id IS NULL" "0"
val "historial íntegro: 4 filas, ninguna borrada" "SELECT COUNT(*) FROM pallet_clasificaciones" "4"
val "anulada conserva motivo y autor" "SELECT CONCAT(anulado, N'|', motivo_anulacion, N'|', anulado_por) FROM pallet_clasificaciones WHERE id = 2" "1|Pallet equivocado|Calidad Uno"
val "inspecciones guardadas (4: 3 con/sin pallets + 1 con pallets inválidos)" "SELECT COUNT(*) FROM registros_control" "4"
val "defectos de la 1.ª clasificación (2)" "SELECT COUNT(*) FROM pallet_clasificacion_defectos WHERE clasificacion_id = 1" "2"
val "copia de FPS verificada guardada" "SELECT CONCAT(fps_verificado, N'|', orden_fabricacion, N'|', np_innpack, N'|', maquina_fps, N'|', operador_fps) FROM pallet_clasificaciones WHERE id = 1" "1|22669|3957|BOBST 142 - 2 (SFM)|LUIS MONTOYA"
val "hora de la tarja sin desfase de zona" "SELECT CONVERT(VARCHAR(19), fecha_tarja, 126) FROM pallet_clasificaciones WHERE id = 1" "2026-11-22T21:08:49"
val "cantidad 0 de FPS = NULL; 1200 se conserva" "SELECT CONCAT(ISNULL(CAST((SELECT cantidad_unidades FROM pallet_clasificaciones WHERE id = 1) AS VARCHAR(20)), N'NULL'), N'|', CAST((SELECT cantidad_unidades FROM pallet_clasificaciones WHERE id = 2) AS VARCHAR(20)))" "NULL|1200.00"

echo "== 3) Migración pendiente: la inspección se guarda igual =="
q -Q "DROP TABLE pallet_clasificacion_defectos; DROP TABLE pallet_clasificaciones; DELETE FROM registro_fallas_visuales; DELETE FROM registros_control;" >/dev/null 2>&1
SALIDA3="$(cd "$RAIZ" && node "$(wp "$AQUI/pallets_localdb_harness.js")" sin_migracion 2>&1)"
val "con las tablas de pallets ausentes se guardaron las inspecciones (4)" "SELECT COUNT(*) FROM registros_control" "4"
echo "$SALIDA3" | grep -q "HARNESS_ERROR" && { ko "arnés sin migración falló"; echo "$SALIDA3" | tail -5; } || ok "arnés sin migración terminó (los errores de pallets quedaron contenidos por el savepoint)"

echo "== 4) Rollback 015 y re-aplicación =="
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets.sql")" >/dev/null 2>&1 || ko "re-aplicar 015 antes del rollback"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets_rollback.sql")" >/dev/null 2>&1 && ok "rollback 015 ejecuta" || ko "rollback 015 falló"
val "tras el rollback no quedan tablas de pallets" "SELECT COUNT(*) FROM sys.tables WHERE name LIKE N'pallet_clasific%'" "0"
val "tras el rollback las inspecciones siguen intactas (4)" "SELECT COUNT(*) FROM registros_control" "4"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets_rollback.sql")" >/dev/null 2>&1 && ok "rollback es idempotente" || ko "rollback no idempotente"
sqlcmd -S "$PIPE" -E -b -d "$DB" -i "$(wp "$MIG/015_clasificacion_pallets.sql")" >/dev/null 2>&1 && ok "re-aplicación tras rollback" || ko "re-aplicación falló"

sqlcmd -S "$PIPE" -E -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END" >/dev/null 2>&1
echo; echo "RESULTADO: $PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
