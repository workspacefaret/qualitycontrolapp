#!/usr/bin/env bash
# Pruebas de la migración 010 en una base AISLADA de LocalDB (calidad_010_test). NUNCA toca producción ni ningún servidor remoto:
# solo se conecta a la instancia LocalDB de esta máquina por named pipe con autenticación de Windows.
# Requiere: sqlcmd (go-sqlcmd), sqllocaldb, python+openpyxl, y el DDL documentado de calidad_db
# (por defecto ../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql, fuera de este repo).
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIG="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MIG/../.." && pwd)"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
DB=calidad_010_test
TMP="${TMPDIR:-/tmp}/010_pruebas"; mkdir -p "$TMP"
SALIDA="$TMP/salida.log"; : > "$SALIDA"

PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"
if [ -z "$PIPE" ]; then sqllocaldb start MSSQLLocalDB >/dev/null; PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"; fi
SERVER="$PIPE"   # tal como lo informa sqllocaldb (ya trae el prefijo np:)

FALLOS=0
wp() { cygpath -m "$1" 2>/dev/null || echo "$1"; }   # sqlcmd es un .exe de Windows: necesita rutas C:/...
q()  { sqlcmd -S "$SERVER" -E -b -d "$DB" "$@"; }      # contra la base de pruebas
sql_file() { # etiqueta archivo [args sqlcmd]
    local et="$1" f="$2"; shift 2
    echo "--- $et" | tee -a "$SALIDA"
    if ! q -i "$(wp "$f")" "$@" 2>&1 | tee -a "$SALIDA" | grep -v '^$'; then :; fi
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "FAIL  $et (exit != 0)" | tee -a "$SALIDA"; FALLOS=$((FALLOS+1)); return 1; fi
}
esperar_falla() { # etiqueta archivo : el script DEBE terminar con error
    local et="$1" f="$2"; shift 2
    echo "--- $et" | tee -a "$SALIDA"
    if q -i "$(wp "$f")" "$@" >>"$SALIDA" 2>&1; then echo "FAIL  $et (debía fallar y terminó bien)" | tee -a "$SALIDA"; FALLOS=$((FALLOS+1)); return 1; fi
    echo "PASS  $et (falló como se esperaba)" | tee -a "$SALIDA"
}
consulta() { q -h -1 -W -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | head -1; }
afirmar() { # etiqueta consulta valor_esperado
    local r; r="$(consulta "$2")"
    if [ "$r" = "$3" ]; then echo "PASS  $1 (= $3)" | tee -a "$SALIDA"; else echo "FAIL  $1: esperado '$3', obtenido '$r'" | tee -a "$SALIDA"; FALLOS=$((FALLOS+1)); fi
}

echo "== 0. Generador: el SQL de la migración coincide con el Excel =="
python -I "$RAIZ/tools/generar_catalogo_eventos_calidad_faret.py" --verificar || FALLOS=$((FALLOS+1))

echo "== 1. Base aislada: esquema documentado de calidad_db + migraciones previas (009) + datos históricos de ejemplo =="
sqlcmd -S "$SERVER" -E -b -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END; CREATE DATABASE $DB COLLATE Latin1_General_100_CI_AI_SC; ALTER DATABASE $DB SET COMPATIBILITY_LEVEL = ${NIVEL_COMPAT:-130}" || exit 2
q -i "$(wp "$DDL")" >/dev/null 2>&1 || { echo "No se pudo cargar el DDL $DDL"; exit 2; }
q -i "$(wp "$MIG/009_client_uuid_idempotencia.sql")" >/dev/null 2>&1 || { echo "No se pudo aplicar la 009"; exit 2; }
sql_file "setup (usuario de la app + histórico)" "$AQUI/010_t_setup.sql"
sql_file "escala real (4161 inspecciones, 399 defectos, 3000 client_uuid)" "$AQUI/010_t_escala.sql"
sql_file "foto ANTES" "$AQUI/010_t_snapshot.sql" -v FASE=antes

afirmar "nivel de compatibilidad de la base de pruebas (130 = SQL Server 2016)" "SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()" "${NIVEL_COMPAT:-130}"
echo "== 2. Aplicar migración 010 =="
sql_file "aplicar 010 (1ª vez)" "$MIG/010_catalogo_eventos_calidad_faret.sql"
sql_file "foto TRAS_010" "$AQUI/010_t_snapshot.sql" -v FASE=tras_010

echo "== 3. Verificación del catálogo, restricciones, auditoría, permisos y bloqueo de los 5 pendientes =="
sql_file "pruebas de catálogo" "$AQUI/010_t_catalogo.sql"

echo "== 4. Histórico y otros módulos intactos =="
sql_file "comparar ANTES vs TRAS_010" "$AQUI/010_t_comparar.sql" -v FASE_A=antes -v FASE_B=tras_010 -v TABLAS=1 -v MODO=aditiva
afirmar "defectos históricos sin id_evento/criticidad" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL OR criticidad IS NOT NULL" "0"
afirmar "399 defectos históricos intactos" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos" "399"
afirmar "4161 inspecciones intactas" "SELECT COUNT(*) FROM dbo.registros_calidad_faret" "4161"
afirmar "3000 client_uuid preservados (únicos)" "SELECT CAST(COUNT(client_uuid) AS NVARCHAR(10)) + N'/' + CAST(COUNT(DISTINCT client_uuid) AS NVARCHAR(10)) FROM dbo.registros_calidad_faret" "3000/3000"

echo "== 5. Idempotencia: re-aplicar no duplica ni pisa ediciones posteriores =="
q -Q "EXEC sp_set_session_context N'usuario', N'tester'; EXEC sp_set_session_context N'motivo', N'edicion entre ejecuciones'; UPDATE dbo.calidad_faret_eventos SET criticidad = N'Critico', defecto = N'Rayas (texto editado).' WHERE id_evento = N'OFF-011'" >/dev/null 2>&1
sql_file "aplicar 010 (2ª vez)" "$MIG/010_catalogo_eventos_calidad_faret.sql"
sql_file "aplicar 010 (3ª vez)" "$MIG/010_catalogo_eventos_calidad_faret.sql"
afirmar "áreas tras re-aplicar" "SELECT COUNT(*) FROM dbo.calidad_faret_areas" "8"
afirmar "eventos tras re-aplicar" "SELECT COUNT(*) FROM dbo.calidad_faret_eventos" "57"
afirmar "auditoría de carga inicial sin duplicados" "SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria WHERE accion = N'CARGA_INICIAL'" "65"
afirmar "edición del catálogo preservada (no se pisa)" "SELECT criticidad + N'|' + defecto FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-011'" "Critico|Rayas (texto editado)."
afirmar "origen del Excel sigue intacto tras la edición" "SELECT criticidad_origen + N'|' + defecto_origen FROM dbo.calidad_faret_eventos WHERE id_evento = N'OFF-011'" "Mayor|Rayas."
q -Q "EXEC sp_set_session_context N'usuario', N'tester'; UPDATE dbo.calidad_faret_eventos SET criticidad = N'Mayor', defecto = N'Rayas.' WHERE id_evento = N'OFF-011'" >/dev/null 2>&1   # deja el catálogo como el Excel
sql_file "foto REAPLICADA" "$AQUI/010_t_snapshot.sql" -v FASE=reaplicada
sql_file "comparar ANTES vs REAPLICADA" "$AQUI/010_t_comparar.sql" -v FASE_A=antes -v FASE_B=reaplicada -v TABLAS=1 -v MODO=aditiva

echo "== 6. Verificación independiente contra el Excel (campo por campo) =="
TAB=$(printf '\t')
q -h -1 -W -s "$TAB" -Q "SET NOCOUNT ON; SELECT id_evento, cod_area, defecto_origen, criticidad_origen, estado_origen, ISNULL(observacion_origen, N''), texto_documento, estado, aprobacion FROM dbo.calidad_faret_eventos ORDER BY id_evento" > "$TMP/eventos.tsv" 2>&1
q -h -1 -W -s "$TAB" -Q "SET NOCOUNT ON; SELECT cod_area, nombre, area_control, orden, estado FROM dbo.calidad_faret_areas ORDER BY orden" > "$TMP/areas.tsv" 2>&1
python -I "$AQUI/010_verificar_contra_excel.py" "$TMP/eventos.tsv" "$TMP/areas.tsv" | tee -a "$SALIDA"
[ "${PIPESTATUS[0]}" -eq 0 ] || FALLOS=$((FALLOS+1))

echo "== 7. Rollback =="
sql_file "datos creados con el catálogo nuevo + copia testigo" "$AQUI/010_t_pre_rollback.sql"
sql_file "foto PRE_ROLLBACK" "$AQUI/010_t_snapshot.sql" -v FASE=pre_rollback
esperar_falla "rollback SIN autorización se niega si hay defectos con id_evento" "$MIG/010_catalogo_eventos_calidad_faret_rollback.sql"
afirmar "tras el rechazo todo sigue en pie (catálogo)" "SELECT COUNT(*) FROM dbo.calidad_faret_eventos" "57"
afirmar "tras el rechazo todo sigue en pie (defectos con evento)" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL" "2"
sed 's/@permitir_con_datos BIT = 0/@permitir_con_datos BIT = 1/' "$MIG/010_catalogo_eventos_calidad_faret_rollback.sql" > "$TMP/rollback_con_datos.sql"
sql_file "rollback con @permitir_con_datos = 1" "$TMP/rollback_con_datos.sql"
sql_file "respaldos y limpieza" "$AQUI/010_t_post_rollback.sql"
sql_file "foto TRAS_ROLLBACK" "$AQUI/010_t_snapshot.sql" -v FASE=tras_rollback
sql_file "comparar PRE_ROLLBACK vs TRAS_ROLLBACK (ninguna fila ni columna original cambia, incluidas las 2 inspecciones nuevas)" "$AQUI/010_t_comparar.sql" -v FASE_A=pre_rollback -v FASE_B=tras_rollback -v TABLAS=1 -v MODO=ninguno
sql_file "comparar objetos ANTES vs TRAS_ROLLBACK (esquema exactamente como al inicio, sin residuos)" "$AQUI/010_t_comparar.sql" -v FASE_A=antes -v FASE_B=tras_rollback -v TABLAS=0 -v MODO=igual
afirmar "las 399 filas históricas de defectos idénticas a la foto inicial" "SELECT CASE WHEN (SELECT CHECKSUM_AGG(CHECKSUM(id, registro_id, defecto)) FROM dbo.registro_calidad_faret_defectos WHERE id <= 399) = (SELECT checksum_contenido FROM dbo.zz_snap WHERE fase = N'antes' AND tabla = N'registro_calidad_faret_defectos') THEN N'iguales' ELSE N'DISTINTAS' END" "iguales"
sql_file "rollback repetido (nada que revertir)" "$MIG/010_catalogo_eventos_calidad_faret_rollback.sql"
afirmar "la cuenta de la app conserva sus permisos preexistentes" "SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id = USER_ID(N'quality_control_backend_sql') AND class = 1 AND OBJECT_NAME(major_id) = N'registro_calidad_faret_defectos'" "2"

echo "== 8. Re-aplicar tras el rollback + regresión completa =="
sleep 2
sql_file "aplicar 010 tras rollback" "$MIG/010_catalogo_eventos_calidad_faret.sql"
sql_file "pruebas de catálogo (regresión)" "$AQUI/010_t_catalogo.sql"
afirmar "catálogo recargado completo" "SELECT COUNT(*) FROM dbo.calidad_faret_eventos" "57"
echo "== 9. Rollback limpio (sin datos nuevos) y re-aplicación final =="
sleep 2
q -Q "DELETE FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL" >/dev/null 2>&1
sql_file "rollback sin autorización especial (no hay datos con evento)" "$MIG/010_catalogo_eventos_calidad_faret_rollback.sql"
sleep 2
sql_file "aplicar 010 (estado final de la prueba)" "$MIG/010_catalogo_eventos_calidad_faret.sql"

echo
if [ "$FALLOS" -eq 0 ]; then echo "RESULTADO: TODAS LAS PRUEBAS PASARON  ($(grep -c '^PASS' "$SALIDA") PASS)"; else echo "RESULTADO: $FALLOS FALLO(S) -- ver $SALIDA"; fi
echo "PASS: $(grep -c '^PASS' "$SALIDA")  FAIL: $(grep -c '^FAIL' "$SALIDA")   (log completo: $SALIDA)"
exit "$FALLOS"
