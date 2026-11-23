# Clasificación de pallets INNPACK — despliegue y rollback

Rama: `feature/clasificacion-pallets-innpack` (commits locales; no empujada). **Nada de esto está aplicado en producción.**

## Orden obligatorio

1. **Migración 015** (DBA/dueño, PowerShell, sobre `calidad_db`): `backend/migrations/015_clasificacion_pallets.sql`. Aditiva e idempotente (se puede re-ejecutar). Crea `pallet_clasificaciones` y `pallet_clasificacion_defectos` + GRANT al usuario `quality_control_backend_sql`. No toca tablas existentes. Respaldar `calidad_db` antes.
   - Verificar: ambas tablas existen y el usuario de la app tiene SELECT/INSERT/UPDATE (clasificaciones) y SELECT/INSERT (defectos).
2. **Backend** (SMB + PM2, flujo habitual con respaldo previo): archivos nuevos `src/utils/clasificacionPallets.js`, `src/controllers/clasificacionPallets.controller.js`, `src/routes/clasificacionPallets.routes.js`; modificados `server.js` (2 líneas), `src/routes/control.routes.js`, `src/controllers/control.controller.js`. **`server.js` de producción tiene cambios ajenos (adminPlanta): aplicar solo las 2 líneas (require + `app.use('/api/pallets', …)`), no sobrescribir el archivo.** Reinicio: `pm2 restart` por el administrador TI.
   - Si se despliega el backend sin la 015: la inspección se guarda igual (los pallets se descartan con `ERROR_AL_GUARDAR`; savepoint). `GET /tarja` y lecturas darán 500/errores hasta aplicarla.
3. **Flutter web**: `flutter build web --release --dart-define=API_BASE_URL=https://api.faret.cl/calidad/api --base-href /` y publicar como siempre (antes `git status`; respaldo `_backup_web_*`). Subir `+N` en `pubspec.yaml` y compilar APK solo si se autoriza (siguiente: `1.0.0+9`).
4. Los clientes antiguos (APK/web viejos) siguen funcionando: no envían `pallets`.

## Verificación posterior
- `GET /api/pallets/tarja/<código real>` → datos de FPS.
- Guardar una inspección con 1 pallet y otra sin pallets; revisar `pallet_clasificaciones` y `GET /api/pallets/clasificaciones` (con token).
- Reenviar el mismo `clientId` → 200 `duplicado`, sin fila nueva.

## Rollback
- Backend: restaurar los archivos respaldados y `pm2 restart` (o quitar las 2 líneas de `server.js`).
- Web/APK: restaurar `_backup_web_*` / reinstalar APK anterior.
- Base de datos: `015_clasificacion_pallets_rollback.sql` elimina solo las dos tablas nuevas (**borra las clasificaciones capturadas**; exportarlas antes si ya hay datos). Las inspecciones no se ven afectadas.

## Riesgos / recomendaciones
- El login de FPS en `.env` es `sa`: crear un usuario SQL de solo lectura (SELECT en las tablas consultadas) y usarlo.
- INNPACK no guarda fotos sin conexión: con pallets con foto y sin red la app avisa y no guarda (igual que la evidencia actual). Sin foto, la cola offline funciona.
- Máx. 30 pallets e idealmente ≤40 fotos por inspección; límite de petición 150 MB (igual que IIS).
- Los modos de autenticación siguen en `observar`; activar `exigir` por separado.
- Prueba en dispositivo real y con sesión real pendientes (solo hubo pruebas automáticas y LocalDB).
