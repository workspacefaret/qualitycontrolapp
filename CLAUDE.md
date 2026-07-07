# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Industrial quality-control app for a corrugated-cardboard packaging plant: a Flutter mobile client (`lib/`) paired with a Node.js/Express + MySQL backend (`backend/`). Operators scan a QR code on a machine, get an auto-generated form based on machine/process, and submit quality-control records — with offline support when plant Wi-Fi or mobile data is unavailable.

## Reglas de trabajo (modo seguro)

El propietario de este repo trabaja en **modo seguro**. Respeta estas reglas en todo momento:

1. **No modifiques archivos sin aprobación explícita.**
2. Antes de cambiar algo, **analiza el problema**.
3. Entrega primero un **plan** con: archivos que cambiarías, motivo del cambio, riesgo y cómo probarlo.
4. **Espera la aprobación** antes de implementar.
5. Implementa **solo un paso a la vez**.
6. Después de cada cambio, **resume exactamente qué modificaste**.
7. **No agregues dependencias nuevas** sin aprobación.
8. **No hagas refactor general.**
9. **No renombres archivos ni carpetas** salvo que se apruebe.
10. **Mantén el estilo actual del proyecto.**

# Comunicación

- Responder siempre en español.
- Ser breve y directo.
- No hacer cambios sin aprobación.
- Explicar el plan antes de implementar.
- Implementar un paso a la vez.
- Mantener la arquitectura existente.
- No introducir sobreingeniería.


## Commands

### Frontend (Flutter, run from repo root)

```
flutter pub get                 # install dependencies
flutter run                     # run on a connected device/emulator
flutter run --dart-define=API_BASE_URL=http://<host>:3000/api   # point at a non-default backend
flutter analyze                 # lint (flutter_lints, see analysis_options.yaml)
flutter test                    # run widget/unit tests
flutter test test/widget_test.dart   # run a single test file
```

Note: `test/widget_test.dart` is unmodified Flutter template boilerplate — it references a `MyApp` class that doesn't exist in this project (the real entry point is `QualityControlApp` in `lib/app/quality_control_app.dart`), so it will fail to compile as-is. There are no other tests in the repo.

### Web build & deploy

The app is also deployed to web, served from a **subpath** (not domain root): `https://workspace.faret.cl/qualitycontrol/`. Production build command (the `--base-href` must match the serving subpath or every asset 404s and the app fails to boot with `_flutter is not defined`):

```
flutter build web --release --dart-define=API_BASE_URL=https://api.faret.cl/calidad/api --base-href /qualitycontrol/
```

In Git Bash on Windows, a leading `/` argument gets mis-expanded to a Windows path (`C:/Program Files/Git/qualitycontrol/`) — prefix the command with `MSYS_NO_PATHCONV=1` if that happens. Deploy by uploading the full contents of `build/web/` to that path, overwriting existing files.

Known gotcha: Flutter web registers a service worker that aggressively caches `main.dart.js`. After redeploying, clients (including yourself while testing) may keep executing an old cached bundle — regular "clear browsing history" does **not** reliably clear Service Worker/Cache Storage. If a deployed change doesn't seem to take effect in the browser but a fresh `curl` of the deployed `main.dart.js` shows the new code, it's this cache: DevTools → Application → Service Workers → Unregister, then Application → Clear storage → Clear site data, then close all tabs of that origin before reopening.

### Backend (Node/Express, run from `backend/`)

```
cd backend
npm install
npm run dev     # nodemon, auto-restart
npm start       # node server.js
```

Backend requires `backend/src/config/database.js` (git-ignored) with a MySQL `mysql2` pool — copy `backend/src/config/database.example.js` and fill in real credentials. It also reads a `.env` for `PORT`/`DB_NAME`/etc. Never commit `database.js` or `.env`.

Production backend runs on Windows behind IIS, reverse-proxied via a URL Rewrite rule in `C:\API WEB\api\calidad\web.config` (`^calidad/(.*)` → `http://localhost:3000/{R:1}`; a sibling rule proxies `^fps/(.*)` → `http://localhost:3002/{R:1}` for an unrelated API hosted from the same site/web.config) — physical `server.js` at `C:\API WEB\api\calidad\server.js`.

**Correction to a previously wrong assumption: this is NOT managed by iisnode.** The Node process is a plain standalone `node.exe` (found at `C:\Program Files\nodejs\node.exe` — not on PATH) that has to be started manually in a console window, e.g.:
```
taskkill /F /IM node.exe
cd "C:\API WEB\api\calidad"
"C:\Program Files\nodejs\node.exe" server.js
```
(or `start "CalidadAPI" cmd /k "C:\Program Files\nodejs\node.exe" server.js` to run it in a background window that survives closing the current session). There is no Windows Service or scheduled task supervising it (confirmed via `sc query` — none exists). Consequences:
- `iisreset` does **NOT** restart this process — it only cycles IIS/w3wp. After editing `server.js` or any file it requires, you must manually `taskkill /F /IM node.exe` and start it again, or the old code keeps serving indefinitely (this looks like "the deploy didn't take effect" but is really "the old process never died").
- If the console window running it is closed, or the process dies for any other reason, the **entire API goes down** with no auto-recovery — IIS proxies to a dead port and returns `502 Bad Gateway`. Verify liveness with `netstat -ano | findstr :3000`.
- TODO (not done yet): wrap it with [NSSM](https://nssm.cc/) as a real Windows service with `AppExit Default Restart` so it survives crashes/reboots.

The IIS site `API` (id 2, bindings `api.faret.cl:80`/`:443`) also hosts several unrelated apps as separate IIS Applications sharing the same site and SSL certificate: `appguardias`, `mejora-continua`, `formularios`, `apifaret`, `qualitycontrol`, `programa-produccion` (plus `calidad`/`fps`, routed via the web.config rewrite rules above rather than as IIS Applications). The certificate renews automatically via scheduled task `win-acme renew (acme-v02.api.letsencrypt.org)` (Let's Encrypt via win-acme). **If that renewal task fails, the cert expires and every app on that site breaks at once** with SSL/TLS trust errors that look like an app bug but aren't — if multiple unrelated production apps go down simultaneously, check this first: `schtasks /Query /TN "\win-acme renew (acme-v02.api.letsencrypt.org)" /V /FO LIST` and `powershell -Command "Get-ChildItem Cert:\LocalMachine\My | Select Subject,NotAfter"`.

### QR label generation (`tools/`, Python)

`tools/generar_qr_maquinas.py` and `tools/generar_qr_controles.py` are standalone scripts (reportlab + qrcode) that generate printable QR labels (PNG + PDF) for machines and quality-control stations into `tools/qr_maquinas/` and `tools/qr_controles/`. The `codigo_qr` string embedded in each label (e.g. `MAQ-TRO-BOBST-142-1`) must match the `codigo_qr` column in the `maquinas` table for the backend's QR lookup to resolve.

## Architecture

### Client structure (`lib/`)

- `app/quality_control_app.dart` — root `MaterialApp`, launches on `WelcomePage`.
- `core/api/` — thin HTTP layer:
  - `api_client.dart` — `ApiClient` wraps `http` GET/POST against `ApiClient.baseUrl`, which is a compile-time `String.fromEnvironment('API_BASE_URL')`. The literal `defaultValue` in source has drifted between local/LAN URLs and the production URL across past commits — always check the current line rather than trusting history, and always build/run with an explicit `--dart-define=API_BASE_URL=...` rather than relying on the default.
  - `catalogos_api.dart` / `control_api.dart` — typed calls to specific endpoints (see below). `ControlApi.guardarRegistro` takes an optional attachment as **`Uint8List? archivoBytes` + `String? archivoNombre`** (not `dart:io File`) and sends it via `http.MultipartFile.fromBytes` — this works unmodified on both Android and web. Do not reintroduce `dart:io`/`File`/path-based file APIs in this file or in the two pages below; `dart:io` doesn't work on Flutter web.
- `core/local/` — SharedPreferences-backed persistence, the backbone of offline support:
  - `offline_catalog_store.dart` — caches the entire catalog (users, QR→machine/process/form contexts, visual parameters, wave types, materials, lab tests) as one JSON blob, seeded on first run from `assets/data/offline_catalog_seed.json` if nothing has been downloaded yet.
  - `cached_users_store.dart` — separate cache of the users list.
  - `pending_records_store.dart` — queues control records created while offline as `{localId, createdAt, endpoint, status, payload}`, to be flushed later.
- `core/network/network_mode_service.dart` — `NetworkModeService.shouldUseOfflineMode()` decides online/offline by checking `connectivity_plus` and then pinging `GET {baseUrl}/health` with a timeout; any failure means offline mode.
- `features/` — screens, one subfolder per flow:
  - `welcome/` — area/operator selection, entry point.
  - `home/home_page.dart` — hub: triggers catalog refresh (`ControlApi.descargarCatalogoOffline`), shows pending-record count, and flushes the pending-records queue (loops `PendingRecordsStore.getPendingRecords()` → `ControlApi.guardarRegistro()` → `removePendingRecord()`, reporting how many synced vs. remain). The area selector also has a `'CALIDAD FARET'` option (alongside `'CALIDAD'`/`'PRODUCCION'`) that skips the QR-scan button entirely and opens `CalidadFaretFormPage` directly.
  - `control_form/` — the core operational flow: `domain/control_context.dart` defines `ControlContext` (machine/process/form + the visual params, wave types, materials, lab tests for that context); `presentation/` has the QR scanners (`qr_scanner_page.dart`, `product_qr_scanner_page.dart`, both using `mobile_scanner`'s `MobileScanner(onDetect: ...)` widget — works as-is on web too), the dynamic form (`control_form_page.dart`) built from the `ControlContext`, and `control_measurements_page.dart` for lab measurements/visual results. Both form pages pick photo/file evidence via `image_picker`/`file_picker` and hold it as `Uint8List? _selectedAttachmentBytes` (via `XFile.readAsBytes()` and `FilePicker.platform.pickFiles(withData: true)`) — never as a `dart:io File`, so it works on web.
  - `calidad_faret/` — a separate, non-QR flow, unrelated to `control_form/`'s `ControlContext`. `presentation/calidad_faret_form_page.dart` is a standalone form (NV Faret, N° pliego/pasada/item, V°B° aprobado, área de control/operador/máquina, defectos por área with up to 5 photo/file attachments via `image_picker`/`file_picker`, held as `List<Uint8List>` — same no-`dart:io` rule applies) posted through `core/api/calidad_faret_api.dart` (`POST {baseUrl}/calidad-faret/registros`, multipart) to its own backend route/controller/tables. `domain/calidad_faret_catalog.dart` holds the dropdown catalogs (areas, operators per area, machines per area, defects per area, tipos de folia) as static Dart data, not fetched from the backend — unlike the rest of the app's catalog, which comes from `catalogos_api.dart`/`OfflineCatalogStore`.

Client never talks to MySQL directly — everything goes through the REST API. When offline, records are written to `PendingRecordsStore` instead of POSTed, and reads fall back to `OfflineCatalogStore`.

### Backend structure (`backend/`)

- `server.js` — Express app entry point. CORS is locked to a hardcoded `allowedOrigins` allowlist (edit this array when adding a new client origin — must include `https://workspace.faret.cl`, the deployed web app's origin, no path/trailing slash); serves `/uploads` statically for uploaded photos; exposes `GET /api/health` (checks the MySQL pool, also used by `NetworkModeService` to decide online/offline — a CORS rejection here makes the web app permanently report "offline mode" even with a working connection) plus the two route groups below.
- `src/config/database.js` (git-ignored, not in repo) — `mysql2/promise` connection pool; `database.example.js` is the template.
- `src/routes/catalogos.routes.js` + `src/controllers/catalogos.controller.js` — `GET /api/catalogos/usuarios`, `/procesos`, `/maquinas`, `/parametros-visuales/:procesoId`, and `/offline` (the combined payload consumed by `OfflineCatalogStore`).
- `src/routes/control.routes.js` + `src/controllers/control.controller.js` — `GET /api/control/contexto/:codigoQr` (resolves a scanned QR to machine/process/form + relevant visual params/wave types/materials/lab tests) and `POST /api/control/registros` (creates a control record; accepts an optional `multipart/form-data` photo via `multer`, stored under `backend/uploads/control/`). Writes are transactional across `registros_control`, `registro_adjuntos`, `registro_fallas_visuales`, and `registro_ensayos` — roll back and delete the uploaded file on any failure.
- `src/routes/calidadFaret.routes.js` + `src/controllers/calidadFaret.controller.js` — `POST /api/calidad-faret/registros`, entirely independent of the `control` flow above: separate tables (`registros_calidad_faret`, `registro_calidad_faret_defectos`, `registro_calidad_faret_adjuntos`, already created in production), separate upload dir `backend/uploads/calidad_faret/` (up to 5 files, 10MB each, via `multer`). Payload arrives as a `payload` JSON string field (not raw JSON body) alongside `archivos` files, since it's `multipart/form-data`. Mounted in `server.js` under `/api/calidad-faret`.

Corrugated-specific fields (wave type, corrugated-specific merma/scrap fields) are only populated when `procesoId === 1`; other processes (Empalcado, Troquelado, Pegado, Termoformado, Paletizado, Producto Terminado — see the machine codes in `tools/generar_qr_maquinas.py`) send `null` for those columns.

### Known repo quirks

- `backend_publish_calidad_faret/` is a manual staging copy of 3 backend files (`server.js`, `src/routes/calidadFaret.routes.js`, `src/controllers/calidadFaret.controller.js`) meant to be copied to the production server (see the IIS/Node deployment notes above). It is **not auto-synced** with `backend/` — when editing any of those 3 files for a real fix (e.g. the CORS `allowedOrigins` array), update both copies, or the one you forgot silently reverts the fix on the next deploy.
- `quality_control/` and `__MACOSX/` at the repo root are a leftover extracted zip copy of this same project (untracked, not part of the build) — ignore them when searching/editing. `flutter analyze` recurses into `quality_control/` too (it has its own unresolved `.dart_tool`) and produces ~1000+ unrelated errors from it — when checking analyzer output, filter to paths starting with `lib\`/`lib/` at the repo root, not `quality_control\`.
- `pubspec.yaml` pins `mobile_scanner: 5.2.3` and `image_picker: 1.2.3` (bumped from older 3.x/0.8.x pins specifically to fix web-target compile errors against the currently installed Flutter/Dart SDK — older pins failed `flutter build web` with errors inside the plugins' own web implementations, unrelated to app code). `environment.sdk` is `">=3.10.0 <4.0.0"` because `image_picker 1.2.3` requires `^3.10.0`. If bumping these further, re-verify `flutter build web --release` actually compiles, not just `flutter analyze`.
