# Clasificación de pallets INNPACK — traspaso de sesión (2026-11-23)

Estado: **implementada, probada y empaquetada; NO desplegada en producción.** Para retomar, leer este archivo, `docs/CLASIFICACION_PALLETS_CONTRATO_API.md` y `_releases/quality_control/pallets_015/README_DESPLIEGUE.md`.

## Qué es
Sección opcional "Clasificación de pallets" (AZUL = en revisión, ROJO = malo/destrucción, VERDE = bueno) dentro de las inspecciones CALIDAD INNPACK y PRODUCCION INNPACK (flujo QR de máquina). **FARET no participa.** Nunca bloquea guardar una inspección. El operador escanea la tarja (`ETIQUETAS_PRODUCCIONES.Codigo` = `<RecordKey>-<n°>`), el backend consulta FPS solo lectura, y la clasificación se guarda en la misma transacción de la inspección (savepoint). Eventos inmutables; vigente = última no anulada; anulación lógica con motivo. Un módulo Photino lo consumirá por API (otra sesión; contrato en `docs/CLASIFICACION_PALLETS_CONTRATO_API.md`).

## Dónde está todo
- Repo: `C:\Users\dcarrasco\Desktop\Proyectos\quality_control`, rama `feature/clasificacion-pallets-innpack` (base `28dc900`). Commits: c80a023, 7ff0f45, d3d8e5f, 766f5ae, a4d69f0, 8084cbc + el de este traspaso.
- Worktrees de trabajo (en el scratchpad de la sesión, pueden desaparecer): `wt_pallets` (rama), `wt_live` (estado publicado de referencia), `wt_build` (rama + capa en vivo, versión +10). El contenido necesario ya está en el paquete.
- Paquete: `C:\Users\dcarrasco\Desktop\Proyectos\_releases\quality_control\pallets_015\`
  - `db/` 015, 015_rollback, `015_prechequeo_SOLO_LECTURA.sql`, `FPS_usuario_solo_lectura_PROPUESTA.sql` (no ejecutada)
  - `backend_nuevo/` (7 archivos), `backend_actual/` (snapshot de producción), `MANIFEST.sha256`, `SHA256SUMS_TODO.txt`
  - `deploy_pallets_backend.sh` (pre / backend --ejecutar / rollback / estado / post), `deploy_lib.ps1`
  - `web_nuevo/` (6 archivos) + `deploy_web_pallets.sh` (simulacro por defecto, --ejecutar, --rollback)
  - `apk/quality_control_1.0.0+10.apk` (+ .sha256) — sin distribuir
  - `deploy_tests/` (arnés aislado), `logs/suite_despliegue_20261123_118OK_0FALLAS.log`
- Carpeta temporal sin borrar (puede borrarla el dueño): `_releases\quality_control\_pruebas_deploy_aisladas_pallets`.

## Resultados verificados (no inventados)
Backend `npm test` 107/107 · SQL real LocalDB (compat. 130) 46/46 · Flutter 70/70 con la capa en vivo, análisis sin errores · humo sobre árbol de producción real + archivos nuevos (401 sin token, adminPlanta presente, límite 429) · suite de despliegue/rollback 118 OK / 0 fallas / 14 escenarios · prevalidación de producción (solo lectura) TODO OK · APK firmado con el cert de siempre (SHA-256 `7799a69a…14e2`).

## Trampas descubiertas (importante)
1. **Front en vivo = rama + código sin commitear del árbol principal** (catálogo de planta FARET: `calidad_faret_form_page.dart`, `calidad_faret_pallet_form_page.dart`, `calidad_faret_planta_api.dart`, `catalogo_planta_faret.dart`, test, `pubspec` +9). Compilar solo la rama borraría eso de producción. El build +10 se hizo sobre esa capa; se verificó que el árbol de referencia reproduce byte a byte el `main.dart.js` publicado (SHA-256 `8047998d8970177d4cefbc3de78eed750148a87842cb96f92da62f0691bc1591`). El `main.dart.js` nuevo es `73769c523896275f784e963858f50614e85551798fdff66f70a01f7b88f79242`.
2. **Web: 6 archivos**, no 4: `flutter_bootstrap.js index.html main.dart.js version.json .last_build_id assets/fonts/MaterialIcons-Regular.otf` (la fuente cambia por los iconos nuevos). `manifest.json` y el catálogo semilla solo difieren en fin de línea: NO copiar.
3. **`server.js` de producción** = base + adminPlanta (2 líneas). El paquete lleva producción + 2 líneas de pallets; no sobrescribir con el de la rama. Los otros 6 archivos son idénticos a la base y se reemplazan enteros. En el árbol principal `server.js` tiene cambios sin commitear: al integrar la rama habrá conflicto trivial.
4. **Mi login de Windows (`AD\dcarrasco`) no tiene acceso a SQL 192.168.1.230.** Respaldo, prechequeo y migración 015 los ejecuta el dueño/DBA por PowerShell, **antes** del backend. No usar otras credenciales.
5. **Calidad corre bajo PM2** (hijo `ProcessContainerFork.js`, PID 5620 al 2026-11-23). El script exige `CALIDAD_PM2_CONFIRMADO=1` solo tras confirmación de TI con `pm2 describe`.
6. **`GET /api/pallets/tarja/:codigo` es público a propósito** (operadores sin sesión, igual que `/orden-fabricacion` y `/bobina`), limitado por IP (`LIMITE_TARJA_POR_MIN`, def. 120). Lectura/anulación usan `autorizar` (modos hoy en `observar`).
7. **FPS usa login `sa`** (`SQL_USER` en el `.env` de SRV-API). Solo lee 7 tablas. Propuesta de login de solo lectura sin ejecutar.
8. **Arnés de pruebas:** una tarea en segundo plano matada por el sistema deja vivo su `run_tests.sh` y servidores falsos en puertos 39100–39110; antes de repetir, comprobar procesos (`bash … run_tests`, `node` en 391xx) y no cerrar los que no sean propios. Además el Gradle daemon del APK retiene ~2 GB: detener los propios al terminar. Con poca memoria libre no lanzar la suite y un build a la vez.
9. Archivos `.md` están en `.gitignore`: se versionan con `git add -f`.

## Pendiente, en orden
1. **Dueño/DBA — Fase A:** respaldo de `calidad_db` + `RESTORE VERIFYONLY` → prechequeo (debe decir "PRECHEQUEO OK") → aplicar 015 → repetir prechequeo. Comandos en README sección A.
2. **TI:** confirmar PM2.
3. **Autorización final explícita del dueño** para Fases B y C (no se ha dado todavía; la última instrucción de la sesión pidió solo guardar contexto y commit/push).
4. Fase B: `CALIDAD_PM2_CONFIRMADO=1 TARJA_PRUEBA=<N-N real> ./deploy_pallets_backend.sh backend --ejecutar` (desde el paquete). Fase C: `bash deploy_web_pallets.sh` (simulacro) y `--ejecutar`.
5. Verificaciones posteriores y **validación en terreno** con operador y tarja real (README, sección "Validación en terreno"): NO realizada.
6. APK +10 a un dispositivo piloto antes de distribuir.
7. Después: módulo Photino (otra sesión), login SQL de solo lectura para FPS, activar modos `exigir` por separado.

## Qué NO está hecho
Migración 015 en producción · backend en producción · web en producción · APK distribuido · validación en terreno · respaldo de `calidad_db` · cambio de credenciales FPS.
