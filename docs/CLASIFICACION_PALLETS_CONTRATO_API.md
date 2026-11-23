# Clasificación de pallets INNPACK — contrato de API (para el módulo Photino)

Base: `{API}/calidad/api/pallets` (mismo host que el resto de la API Calidad). Todas las respuestas: `{ ok, data }` o `{ ok:false, code, message }`.
Alcance: solo INNPACK (Calidad y Producción, flujo QR de máquina). FARET no participa.

## Modelo de datos

- **Evento**: cada clasificación es una fila en `pallet_clasificaciones` (nunca se actualiza el color ni se borra). Reclasificar = nueva fila.
- **Vigente**: la última clasificación **no anulada** de cada `palletCodigo`. Un pallet tiene a lo sumo una vigente.
- **Anulación**: lógica (`anulado=1`, con `anuladoEn`, `anuladoPor`, `motivoAnulacion`). Sigue visible con `incluirAnuladas=1`.
- Colores: `AZUL` (en revisión), `ROJO` (malo / destrucción), `VERDE` (bueno). Ninguno exige defecto, observación ni foto.
- `palletCodigo` = QR de la tarja = `ETIQUETAS_PRODUCCIONES.Codigo` de FPS = `<RecordKey>-<n° etiqueta>` (ej. `466568-1`).
- `fps`: copia de los datos de FPS al clasificar. `fps.verificado=false` significa que FPS estaba caído y se conservó lo que envió la app.
- Responsable, proceso, máquina, NP y turno vienen de la inspección asociada (`inspeccion`).

## Autenticación

Lectura: mismo JWT que el resto (`Authorization: Bearer`), roles ADMIN/ADMIN_TI/CALIDAD/INSPECTOR/CONSULTA/OPERADOR (modo `AUTH_CONSULTAS_MODO`).
Anulación: ADMIN/ADMIN_TI/CALIDAD (modo `AUTH_BORRADO_MODO`). `fotoUrl` llega **ya firmada** (vence en ~10 min); volver a consultar para renovarla.
`GET /tarja/:codigo` es público (lo usan los formularios, igual que `/orden-fabricacion` y `/bobina`).

## Endpoints

### GET `/clasificaciones`
Listado paginado. Filtros (todos opcionales, combinables):

| parámetro | significado |
|---|---|
| `desde`, `hasta` | `YYYY-MM-DD`, por fecha de clasificación (hasta inclusive) |
| `color` | `AZUL`/`ROJO`/`VERDE` |
| `procesoId`, `maquinaId`, `usuarioId` | de la inspección (usuarioId = inspector) |
| `operador` | texto (LIKE) sobre inspector u operador FPS |
| `np` | exacto sobre NP de la inspección, NP Faret/INNPACK u OF |
| `defectoId` | clasificaciones que incluyen ese defecto |
| `palletCodigo` | un pallet |
| `vista` | `eventos` (defecto: todos los eventos no anulados) · `vigentes` (solo la última de cada pallet) |
| `incluirAnuladas` | `1` para incluir anuladas (con `vista=eventos`) |
| `pagina`, `limite` | 1.., máx. 200 (defecto 50) |

Respuesta: `data = { total, pagina, limite, items[] }`, orden `id` descendente. Cada item:

```json
{
  "id": 12, "registroId": 3456, "palletCodigo": "466568-1", "recordKey": 466568, "nEtiqueta": 1,
  "color": "AZUL", "vigente": true, "anulado": false, "anuladoEn": null, "anuladoPor": null, "motivoAnulacion": null,
  "observacion": "golpe en esquina", "fotoUrl": "https://…/uploads/…?exp=…&sig=…", "clasificadoEn": "2026-11-23T10:30:00",
  "inspeccion": { "usuarioId": 4, "inspector": "…", "procesoId": 3, "proceso": "Troquelado", "maquinaId": 9, "maquina": "…",
                  "np": "3957", "turno": "A", "area": "CALIDAD INNPACK", "estadoValidacion": "…" },
  "fps": { "verificado": true, "ordenFabricacion": "22669", "npFaret": "22669", "npInnpack": "3957", "cliente": "…", "itemNp": "…",
           "codigoProducto": "…", "producto": "…", "proceso": "TROQUEL", "maquina": "BOBST 142 - 2 (SFM)", "operador": "…",
           "fechaTarja": "2026-11-22T21:08:49", "cantidadUnidades": 1200, "totalEtiquetas": 25 },
  "defectos": [ { "id": 7, "nombre": "Descalse", "criticidad": "mayor" } ]
}
```
Fechas: texto `YYYY-MM-DDTHH:mm:ss` en hora local de planta (sin zona).

### GET `/clasificaciones/resumen`
Mismos filtros. `data = { vista, totales{azul,rojo,verde,total}, porProceso[{id,nombre,azul,rojo,verde,total}], porMaquina[…], porDia[{dia,azul,rojo,verde,total}] }`.

### GET `/clasificaciones/defectos`
Mismos filtros. `data = { porDefecto[{color,defectoId,nombre,criticidad,cantidad}], sinDefecto[{color,cantidad}] }`.

### GET `/clasificaciones/:id`
Detalle + historial completo del pallet: `data = { …item, historial[items del pallet en orden cronológico] }`. 404 `NO_ENCONTRADA`.

### GET `/historial/:codigo`
`data = [items]` del pallet (incluye anuladas). 400 `CODIGO_INVALIDO` si no es `N-N`.

### POST `/clasificaciones/:id/anular`
Body `{ "motivo": "texto obligatorio (≤250)" }`. Marca la clasificación como anulada (no borra). 200 `{ ok, data:{id} }`; 400 `MOTIVO_REQUERIDO`; 404 `NO_ENCONTRADA_O_YA_ANULADA`.
Reclasificar desde Photino no existe a propósito: la clasificación nace en la inspección (app). Si se necesita, requiere endpoint nuevo.

### GET `/tarja/:codigo` (público; lo usa la app)
Acepta `N-N` o solo `N` (registro). `data` = datos de FPS + `estadoActual{color,clasificadoEn}`; o `{requiereEtiqueta:true, etiquetas[]}`.
Errores: `CODIGO_INVALIDO` 400, `TARJA_NO_ENCONTRADA` 404, `TARJA_SIN_REGISTRO_PRODUCCION` 404, `FPS_NO_DISPONIBLE` 503.

## Guardado (referencia; lo hace la app, no Photino)

`POST /api/control/registros` acepta `pallets: [{codigo, color, defectos:[ids], observacion, fotoIndex, datosFps}]` y fotos en el campo multipart `fotosPallet`.
Respuesta 201 incluye `data.pallets{guardados, ignorados[{codigo,motivo}]}`. Motivos de descarte: `COLOR_INVALIDO, CODIGO_INVALIDO, TARJA_NO_ENCONTRADA, TARJA_SIN_REGISTRO_PRODUCCION, REPETIDO_EN_LA_INSPECCION, MAXIMO_PALLETS_EXCEDIDO, ERROR_AL_GUARDAR`. Un pallet inválido nunca impide guardar la inspección. Reintentos con el mismo `clientId` devuelven 200 `duplicado`.

## Sugerencia de pantallas Photino
Lista (filtros arriba + vista Eventos/Vigentes), tarjetas de totales (`resumen.totales`), gráficos por proceso/máquina/día, ranking de defectos (`/defectos`), detalle con línea de tiempo (`historial`) y botón Anular (solo roles con permiso).
