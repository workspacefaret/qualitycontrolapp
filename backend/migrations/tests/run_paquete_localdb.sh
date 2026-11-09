#!/usr/bin/env bash
# Prueba el PAQUETE deploy/calidad-faret-010 de punta a punta contra una base AISLADA de LocalDB (calidad_pkg_test).
# Flujo: manifiesto -> preflight -> respaldo -> verificar respaldo -> aplicar -> verificacion posterior -> rollback -> reaplicar.
# Incluye pruebas negativas (confirmacion equivocada, sin respaldo, manifiesto alterado, doble aplicacion).
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIG="$(cd "$AQUI/.." && pwd)"
RAIZ="$(cd "$MIG/../.." && pwd)"
PKG="$RAIZ/deploy/calidad-faret-010"
DDL="${DDL_CALIDAD:-$RAIZ/../calidad_sqlserver_migration/sqlserver/calidad_sqlserver_schema.sql}"
DB=calidad_pkg_test
SRVPS='(localdb)\MSSQLLocalDB'
BAKDIR="$(cygpath -w "${TMPDIR:-/tmp}/pkg_bak" 2>/dev/null || echo /tmp/pkg_bak)"
mkdir -p "$(cygpath -u "$BAKDIR")"
PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"
[ -z "$PIPE" ] && { sqllocaldb start MSSQLLocalDB >/dev/null; PIPE="$(sqllocaldb i MSSQLLocalDB | sed -n 's/^Instance pipe name: *//p' | tr -d '\r')"; }
wp() { cygpath -m "$1"; }
q() { sqlcmd -S "$PIPE" -E -b -d "$DB" "$@"; }
FALLOS=0; PASS=0
ok() { echo "PASS  $1"; PASS=$((PASS+1)); }
ko() { echo "FAIL  $1"; FALLOS=$((FALLOS+1)); }
ps() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$PKG/$1")" "${@:2}" 2>&1; }   # 00..06
debe_ir() { local et="$1"; shift; local out; out="$(ps "$@")"; local rc=$?; [ $rc -eq 0 ] && ok "$et" || { ko "$et (rc=$rc)"; echo "$out" | tail -15; }; }
debe_fallar() { local et="$1"; shift; local out; out="$(ps "$@")"; local rc=$?; [ $rc -ne 0 ] && ok "$et (falló como se esperaba)" || { ko "$et (debía fallar)"; echo "$out" | tail -8; }; }
cuenta() { q -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '\r' | head -1; }
afirmar() { local r; r="$(cuenta "$2")"; [ "$r" = "$3" ] && ok "$1 (= $3)" || ko "$1: esperado '$3', obtenido '$r'"; }

echo "== 0. Base aislada con escala real =="
sqlcmd -S "$PIPE" -E -b -Q "IF DB_ID('$DB') IS NOT NULL BEGIN ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB; END; CREATE DATABASE $DB COLLATE Latin1_General_100_CI_AI_SC; ALTER DATABASE $DB SET COMPATIBILITY_LEVEL = 130" || exit 2
q -i "$(wp "$DDL")" >/dev/null 2>&1 || { echo "No se pudo cargar el DDL"; exit 2; }
q -i "$(wp "$MIG/009_client_uuid_idempotencia.sql")" >/dev/null 2>&1 || { echo "No se pudo aplicar la 009"; exit 2; }
q -i "$(wp "$AQUI/010_t_setup.sql")" >/dev/null 2>&1 || { echo "setup falló"; exit 2; }
q -i "$(wp "$AQUI/010_t_escala.sql")" | grep -i "pass\|fail"
rm -f "$PKG"/salida/*.json "$PKG"/salida/*.txt 2>/dev/null

echo "== 1. Manifiesto =="
(cd "$RAIZ" && python -I deploy/calidad-faret-010/Preparar-Paquete.py --verificar >/dev/null 2>&1) && ok "manifiesto regenerado coincide" || echo "(sin Preparar-Paquete.py: se omite)"
debe_ir "00 manifiesto OK" 00_Verificar-Manifiesto.ps1

COMUN=(-Servidor "$SRVPS" -Base "$DB")
FRASE_BASE="$(q -h -1 -W -Q "SET NOCOUNT ON; SELECT @@SERVERNAME" | tr -d '\r' | head -1)"

echo "== 2. Sin preflight no se respalda ni se aplica =="
debe_fallar "02 sin preflight" 02_Respaldo.ps1 "${COMUN[@]}" -RutaRespaldo "$BAKDIR" -Confirmar "x"
debe_fallar "04 sin preflight/respaldo" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "x"

echo "== 3. Preflight (solo lectura) =="
debe_ir "01 preflight" 01_Preflight.ps1 "${COMUN[@]}" -UsuarioApp quality_control_backend_sql
ls "$PKG"/salida/preflight_ok_*.json >/dev/null 2>&1 && ok "evidencia preflight_ok generada" || ko "sin evidencia preflight_ok"
afirmar "preflight no cambió nada (sin objetos 010)" "SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'calidad_faret[_]%eventos%'" "0"

echo "== 4. Respaldo =="
debe_fallar "02 confirmación equivocada" 02_Respaldo.ps1 "${COMUN[@]}" -RutaRespaldo "$BAKDIR" -Confirmar "si"
debe_fallar "04 sin respaldo verificado" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "x"
debe_ir "02 respaldo" 02_Respaldo.ps1 "${COMUN[@]}" -RutaRespaldo "$BAKDIR" -SinCompresion -Confirmar "RESPALDAR $DB EN $FRASE_BASE"
debe_ir "03 verificar respaldo" 03_Verificar-Respaldo.ps1 "${COMUN[@]}"
ls "$(cygpath -u "$BAKDIR")"/${DB}_pre010_*.bak >/dev/null 2>&1 && ok "archivo .bak existe" || ko "no hay .bak"

echo "== 5. Aplicar =="
debe_fallar "04 confirmación equivocada" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "APLICAR"
afirmar "tras confirmación equivocada no hay 010" "SELECT COUNT(*) FROM sys.tables WHERE name = 'calidad_faret_eventos'" "0"
debe_ir "04 aplicar" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "APLICAR 010 EN $FRASE_BASE $DB"
afirmar "57 eventos" "SELECT COUNT(*) FROM dbo.calidad_faret_eventos" "57"
debe_fallar "04 doble aplicación rechazada" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "APLICAR 010 EN $FRASE_BASE $DB"
debe_ir "05 verificación posterior" 05_Verificacion-Posterior.ps1 "${COMUN[@]}"

echo "== 6. Rollback =="
debe_fallar "06 confirmación equivocada" 06_Rollback.ps1 "${COMUN[@]}" -Confirmar "no"
debe_ir "06 rollback" 06_Rollback.ps1 "${COMUN[@]}" -Confirmar "REVERTIR 010 EN $FRASE_BASE $DB"
afirmar "sin objetos 010" "SELECT COUNT(*) FROM sys.tables WHERE name IN ('calidad_faret_eventos','calidad_faret_areas')" "0"
afirmar "4161 inspecciones" "SELECT COUNT(*) FROM dbo.registros_calidad_faret" "4161"
afirmar "399 defectos" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos" "399"
afirmar "3000 client_uuid" "SELECT COUNT(DISTINCT client_uuid) FROM dbo.registros_calidad_faret" "3000"

echo "== 7. Re-aplicar y rollback con datos =="
debe_ir "04 re-aplicar" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "APLICAR 010 EN $FRASE_BASE $DB"
q -Q "INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT TOP 1 r.id, e.defecto, e.id_evento, e.criticidad FROM dbo.registros_calidad_faret r JOIN dbo.calidad_faret_areas a ON a.area_control = r.area_defecto JOIN dbo.calidad_faret_eventos e ON e.cod_area = a.cod_area JOIN dbo.vw_calidad_faret_eventos_operables v ON v.id_evento = e.id_evento WHERE r.presenta_defectos = 1 ORDER BY r.id" 2>&1 | head -3
afirmar "defecto nuevo con catálogo" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL" "1"
debe_fallar "06 rollback se niega con datos" 06_Rollback.ps1 "${COMUN[@]}" -Confirmar "REVERTIR 010 EN $FRASE_BASE $DB"
debe_ir "06 rollback -PermitirConDatos" 06_Rollback.ps1 "${COMUN[@]}" -PermitirConDatos -Confirmar "REVERTIR 010 EN $FRASE_BASE $DB"
afirmar "respaldos bak010 de defectos_evento (uno por rollback)" "SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'bak010[_]%[_]defectos[_]evento'" "2"
afirmar "400 defectos (399 + 1 nuevo conservado)" "SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos" "400"

echo "== 8. Manifiesto alterado =="
cp "$PKG/sql/010_catalogo_eventos_calidad_faret.sql" "${TMPDIR:-/tmp}/010_orig.sql"
echo "-- alterado" >> "$PKG/sql/010_catalogo_eventos_calidad_faret.sql"
debe_fallar "00 detecta archivo alterado" 00_Verificar-Manifiesto.ps1
debe_fallar "04 se niega con paquete alterado" 04_Aplicar-Migracion.ps1 "${COMUN[@]}" -Confirmar "x"
cp "${TMPDIR:-/tmp}/010_orig.sql" "$PKG/sql/010_catalogo_eventos_calidad_faret.sql"
debe_ir "00 manifiesto OK tras restaurar" 00_Verificar-Manifiesto.ps1

echo; echo "RESULTADO PAQUETE: PASS=$PASS FAIL=$FALLOS"
sqlcmd -S "$PIPE" -E -Q "ALTER DATABASE $DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE $DB" >/dev/null 2>&1
rm -f "$(cygpath -u "$BAKDIR")"/${DB}_pre010_*.bak
rm -f "$PKG"/salida/*.json "$PKG"/salida/*.txt "$PKG"/logs/*.log 2>/dev/null
[ $FALLOS -eq 0 ]
