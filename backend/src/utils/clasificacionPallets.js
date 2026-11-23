// Clasificación de pallets (AZUL / ROJO / VERDE) en las inspecciones INNPACK (flujo QR de máquina).
// - Consulta FPS EXCLUSIVAMENTE en lectura y con parámetros (nunca se concatena el código del QR).
// - Valida e inserta las clasificaciones dentro de la MISMA transacción de la inspección.
// - La clasificación es OPCIONAL: nada de lo que ocurra aquí puede impedir guardar la inspección.
const fs = require('fs');
const path = require('path');
const { getSqlServerPool, sql: fpsSql } = require('../config/sqlServerPool');
const { sql } = require('../config/calidadSqlServerPool');

const COLORES = ['AZUL', 'ROJO', 'VERDE'];
const MAX_PALLETS = 30;
const MAX_DEFECTOS = 20;
const MAX_ETIQUETAS_LISTADAS = 200;

// El QR de la tarja de proceso contiene ETIQUETAS_PRODUCCIONES.Codigo = "<registro de producción>-<n° de etiqueta>"
// (confirmado en FPS: único, sin repetidos). También se acepta el número de registro solo.
const RE_PALLET = /^(\d{1,12})-(\d{1,4})$/;
const RE_REGISTRO = /^\d{1,12}$/;

const interpretarCodigo = (texto) => {
    const t = typeof texto === 'string' ? texto.trim() : '';
    const p = RE_PALLET.exec(t);
    if (p) return { tipo: 'pallet', codigo: t, recordKey: p[1], nEtiqueta: Number(p[2]) };
    if (RE_REGISTRO.test(t)) return { tipo: 'registro', recordKey: t };
    return null;
};

// ---- FPS (solo lectura) ---------------------------------------------------------------------------------------------
const SQL_TARJA_FPS = `
SELECT TOP 1
  E.Codigo AS codigo, E.CodigoPadre AS record_key, E.Item AS n_etiqueta, E.Cantidad AS cantidad,
  (SELECT COUNT(*) FROM ETIQUETAS_PRODUCCIONES T WHERE T.CodigoPadre = E.CodigoPadre) AS total_etiquetas,
  W.Status AS registro_activo, W.SetupStartDate AS fecha_tarja,
  M.OrdenTrabajo AS orden_fabricacion, M.NotaVentaFaret AS np_faret, M.NotaVentaInnpack AS np_innpack, M.RazonSocial AS cliente,
  P.NrPl AS item_np, P.ItemCode AS codigo_producto, P.ItemName AS producto,
  WEB.Proceso AS proceso, L.bez AS maquina, U.Nombre_Comp AS operador
FROM ETIQUETAS_PRODUCCIONES E
INNER JOIN WorkOrderRecords W ON CAST(W.RecordKey AS nvarchar(50)) = E.CodigoPadre
LEFT JOIN ZZZProcesosProductivos P ON P.Id_Proceso = W.WorkOrderKey
LEFT JOIN ZZZMasterOT M ON M.OrdenTrabajo = P.OrdenTrabajo
LEFT JOIN ZZZListaMaquina L ON L.aplatz_id = W.ResourceKey
LEFT JOIN ZZZProcesosWeb WEB ON WEB.ID = L.ID_ProcesosWeb
LEFT JOIN ZZZUsuarios U ON U.ID = W.UserKey
WHERE E.Codigo = @codigo`;

const SQL_ETIQUETA_EXISTE = 'SELECT TOP 1 1 AS x FROM ETIQUETAS_PRODUCCIONES WHERE Codigo = @codigo';

const SQL_ETIQUETAS_DEL_REGISTRO = `
SELECT TOP ${MAX_ETIQUETAS_LISTADAS} Codigo AS codigo, Item AS n_etiqueta, Cantidad AS cantidad
FROM ETIQUETAS_PRODUCCIONES
WHERE CodigoPadre = @recordKey
ORDER BY Orden`;

// FPS guarda hora local en columnas datetime; el driver las entrega como si fueran UTC. Se intercambian como
// "YYYY-MM-DDTHH:mm:ss" (hora de pared, sin zona) para que la app muestre la misma hora que la tarja impresa.
const aHoraPared = (d) => (d instanceof Date && !isNaN(d) ? d.toISOString().slice(0, 19) : null);
const desdeHoraPared = (s) => {
    if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(s)) return null;
    const d = new Date(`${s.slice(0, 19)}Z`);
    return isNaN(d) ? null : d;
};

const texto = (v, max) => {
    if (v === null || v === undefined) return null;
    const t = String(v).trim();
    return t === '' ? null : t.slice(0, max);
};

const numeroONulo = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : null; // 0 = "sin cantidad" en las etiquetas de FPS
};

const datosDeFila = (f) => ({
    codigo: f.codigo,
    recordKey: f.record_key,
    nEtiqueta: f.n_etiqueta,
    totalEtiquetas: f.total_etiquetas,
    cantidad: numeroONulo(f.cantidad),
    fechaTarja: aHoraPared(f.fecha_tarja),
    ordenFabricacion: texto(f.orden_fabricacion, 30),
    npFaret: f.np_faret ? String(f.np_faret) : null,
    npInnpack: f.np_innpack ? String(f.np_innpack) : null,
    cliente: texto(f.cliente, 255),
    itemNp: texto(f.item_np, 20),
    codigoProducto: texto(f.codigo_producto, 100),
    producto: texto(f.producto, 255),
    proceso: texto(f.proceso, 100),
    maquina: texto(f.maquina, 150),
    operador: texto(f.operador, 150),
    registroActivo: f.registro_activo !== false,
});

// Resultado: { estado: 'ok', datos } | { estado: 'no_existe' } | { estado: 'sin_registro' } | { estado: 'error', error }
const consultarTarjaFps = async (codigo) => {
    try {
        const pool = await getSqlServerPool();
        const r = await pool.request().input('codigo', fpsSql.NVarChar(50), codigo).query(SQL_TARJA_FPS);
        if (r.recordset[0]) return { estado: 'ok', datos: datosDeFila(r.recordset[0]) };
        const e = await pool.request().input('codigo', fpsSql.NVarChar(50), codigo).query(SQL_ETIQUETA_EXISTE);
        return { estado: e.recordset.length > 0 ? 'sin_registro' : 'no_existe' };
    } catch (error) {
        return { estado: 'error', error: error.message };
    }
};

const consultarEtiquetasDelRegistro = async (recordKey) => {
    const pool = await getSqlServerPool();
    const r = await pool.request().input('recordKey', fpsSql.NVarChar(50), recordKey).query(SQL_ETIQUETAS_DEL_REGISTRO);
    return r.recordset.map((f) => ({ codigo: f.codigo, nEtiqueta: f.n_etiqueta, cantidad: numeroONulo(f.cantidad) }));
};

// ---- Guardado dentro de la transacción de la inspección ---------------------------------------------------------------
const SQL_DEFECTOS_VALIDOS = (n) => `
SELECT id FROM parametros_control_visual
WHERE proceso_id = @procesoId AND activo = 1 AND empresa IS NULL AND id IN (${Array.from({ length: n }, (_, i) => `@d${i}`).join(', ')})`;

// Prepara (sin tocar la transacción) las clasificaciones válidas y las descartadas con su motivo.
// Nunca lanza: ante cualquier problema el pallet se descarta y se informa, la inspección se guarda igual.
const resolverPallets = async ({ pallets, procesoId, poolCalidad, fotos = [] }) => {
    const validos = [];
    const ignorados = [];
    const vistos = new Set();
    const lista = Array.isArray(pallets) ? pallets.slice(0, MAX_PALLETS) : [];
    if (Array.isArray(pallets) && pallets.length > MAX_PALLETS) {
        ignorados.push({ codigo: null, motivo: 'MAXIMO_PALLETS_EXCEDIDO' });
    }

    for (const item of lista) {
        const crudo = item && typeof item === 'object' ? item : {};
        const parsed = interpretarCodigo(crudo.codigo);
        const etiqueta = parsed && parsed.tipo === 'pallet' ? parsed : null;
        const codigoMostrado = texto(crudo.codigo, 50);

        const color = typeof crudo.color === 'string' ? crudo.color.trim().toUpperCase() : '';
        if (!COLORES.includes(color)) { ignorados.push({ codigo: codigoMostrado, motivo: 'COLOR_INVALIDO' }); continue; }
        if (!etiqueta) { ignorados.push({ codigo: codigoMostrado, motivo: 'CODIGO_INVALIDO' }); continue; }
        if (vistos.has(etiqueta.codigo)) { ignorados.push({ codigo: etiqueta.codigo, motivo: 'REPETIDO_EN_LA_INSPECCION' }); continue; }
        vistos.add(etiqueta.codigo);

        // El servidor re-consulta FPS: no se confía en los datos que mande el cliente.
        const fps = await consultarTarjaFps(etiqueta.codigo);
        if (fps.estado === 'no_existe') { ignorados.push({ codigo: etiqueta.codigo, motivo: 'TARJA_NO_ENCONTRADA' }); continue; }
        if (fps.estado === 'sin_registro') { ignorados.push({ codigo: etiqueta.codigo, motivo: 'TARJA_SIN_REGISTRO_PRODUCCION' }); continue; }

        let snap;
        let verificado;
        if (fps.estado === 'ok') {
            snap = fps.datos;
            verificado = true;
        } else {
            // FPS no respondió: se conservan los datos que la app capturó al escanear, marcados como no verificados.
            console.warn(`FPS no disponible al clasificar ${etiqueta.codigo}: ${fps.error}`);
            const s = crudo.datosFps && typeof crudo.datosFps === 'object' ? crudo.datosFps : {};
            snap = {
                ordenFabricacion: texto(s.ordenFabricacion, 30), npFaret: texto(s.npFaret, 30), npInnpack: texto(s.npInnpack, 30),
                cliente: texto(s.cliente, 255), itemNp: texto(s.itemNp, 20), codigoProducto: texto(s.codigoProducto, 100),
                producto: texto(s.producto, 255), proceso: texto(s.proceso, 100), maquina: texto(s.maquina, 150),
                operador: texto(s.operador, 150), fechaTarja: texto(s.fechaTarja, 19), cantidad: numeroONulo(s.cantidad),
                totalEtiquetas: Number.isInteger(s.totalEtiquetas) ? s.totalEtiquetas : null,
            };
            verificado = false;
        }

        let defectos = [];
        const pedidos = Array.isArray(crudo.defectos) ? [...new Set(crudo.defectos.map(Number).filter(Number.isInteger))].slice(0, MAX_DEFECTOS) : [];
        if (pedidos.length > 0) {
            try {
                const req = poolCalidad.request().input('procesoId', sql.Int, procesoId);
                pedidos.forEach((id, i) => req.input(`d${i}`, sql.Int, id));
                const r = await req.query(SQL_DEFECTOS_VALIDOS(pedidos.length));
                defectos = r.recordset.map((x) => x.id);
            } catch (error) {
                console.warn(`No se pudieron validar los defectos de ${etiqueta.codigo}: ${error.message}`);
            }
        }

        const fotoIndex = Number.isInteger(crudo.fotoIndex) ? crudo.fotoIndex : null;
        validos.push({
            etiqueta, color, defectos, snap, verificado,
            observacion: texto(crudo.observacion, 500),
            foto: fotoIndex !== null && fotos[fotoIndex] ? fotos[fotoIndex] : null,
        });
    }
    return { validos, ignorados };
};

// Inserta las clasificaciones ya resueltas. Va protegida por un SAVEPOINT: si algo falla (p. ej. la migración 015 aún no
// aplicada) se deshace solo la clasificación y la inspección se guarda igual. Devuelve { guardados, ignorados }.
const insertarClasificaciones = async (transaction, registroId, { validos, ignorados }) => {
    const guardados = [];
    if (validos.length === 0) return { guardados, ignorados };

    await new sql.Request(transaction).query('SAVE TRANSACTION pallets_clasificacion');
    try {
        for (const v of validos) {
            const s = v.snap;
            const r = await new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('palletCodigo', sql.NVarChar(50), v.etiqueta.codigo)
                .input('recordKey', sql.NVarChar(50), v.etiqueta.recordKey)
                .input('nEtiqueta', sql.Int, v.etiqueta.nEtiqueta)
                .input('color', sql.NVarChar(5), v.color)
                .input('observacion', sql.NVarChar(500), v.observacion)
                .input('fotoNombreOriginal', sql.NVarChar(255), v.foto ? v.foto.originalname : null)
                .input('fotoNombreArchivo', sql.NVarChar(255), v.foto ? v.foto.filename : null)
                .input('fotoRuta', sql.NVarChar(500), v.foto ? `/uploads/control/${v.foto.filename}` : null)
                .input('fotoMime', sql.NVarChar(100), v.foto ? v.foto.mimetype : null)
                .input('fotoTamano', sql.Int, v.foto ? v.foto.size : null)
                .input('fpsVerificado', sql.Bit, v.verificado)
                .input('ordenFabricacion', sql.NVarChar(30), s.ordenFabricacion || null)
                .input('npFaret', sql.NVarChar(30), s.npFaret || null)
                .input('npInnpack', sql.NVarChar(30), s.npInnpack || null)
                .input('cliente', sql.NVarChar(255), s.cliente || null)
                .input('itemNp', sql.NVarChar(20), s.itemNp || null)
                .input('codigoProducto', sql.NVarChar(100), s.codigoProducto || null)
                .input('producto', sql.NVarChar(255), s.producto || null)
                .input('procesoFps', sql.NVarChar(100), s.proceso || null)
                .input('maquinaFps', sql.NVarChar(150), s.maquina || null)
                .input('operadorFps', sql.NVarChar(150), s.operador || null)
                .input('fechaTarja', sql.DateTime2, desdeHoraPared(s.fechaTarja))
                .input('cantidad', sql.Decimal(18, 2), s.cantidad || null)
                .input('totalEtiquetas', sql.Int, s.totalEtiquetas || null)
                .query(`
                INSERT INTO pallet_clasificaciones
                  (registro_id, pallet_codigo, record_key, n_etiqueta, color, observacion,
                   foto_nombre_original, foto_nombre_archivo, foto_ruta, foto_mime_type, foto_tamano_bytes,
                   fps_verificado, orden_fabricacion, np_faret, np_innpack, cliente, item_np, codigo_producto, producto,
                   proceso_fps, maquina_fps, operador_fps, fecha_tarja, cantidad_unidades, total_etiquetas)
                OUTPUT INSERTED.id
                VALUES
                  (@registroId, @palletCodigo, @recordKey, @nEtiqueta, @color, @observacion,
                   @fotoNombreOriginal, @fotoNombreArchivo, @fotoRuta, @fotoMime, @fotoTamano,
                   @fpsVerificado, @ordenFabricacion, @npFaret, @npInnpack, @cliente, @itemNp, @codigoProducto, @producto,
                   @procesoFps, @maquinaFps, @operadorFps, @fechaTarja, @cantidad, @totalEtiquetas)`);
            const id = r.recordset[0].id;

            for (const parametroId of v.defectos) {
                await new sql.Request(transaction)
                    .input('clasificacionId', sql.Int, id)
                    .input('parametroId', sql.Int, parametroId)
                    .query('INSERT INTO pallet_clasificacion_defectos (clasificacion_id, parametro_id) VALUES (@clasificacionId, @parametroId)');
            }
            guardados.push({ id, codigo: v.etiqueta.codigo, color: v.color });
        }
        return { guardados, ignorados };
    } catch (error) {
        console.error(`No se pudieron guardar las clasificaciones de pallets (la inspección se guarda igual): ${error.message}`);
        try { await new sql.Request(transaction).query('ROLLBACK TRANSACTION pallets_clasificacion'); } catch (_) { }
        return {
            guardados: [],
            ignorados: [...ignorados, ...validos.map((v) => ({ codigo: v.etiqueta.codigo, motivo: 'ERROR_AL_GUARDAR' }))],
        };
    }
};

// Borra las fotos de pallets que no quedaron asociadas a ninguna clasificación guardada.
const borrarFotosNoUsadas = (fotos, guardados, resueltos) => {
    const usadas = new Set();
    if (guardados.length > 0) {
        for (const v of resueltos.validos) if (v.foto) usadas.add(v.foto.filename);
    }
    for (const f of fotos) {
        if (!usadas.has(f.filename)) { try { fs.unlinkSync(f.path || path.join(f.destination || '', f.filename)); } catch (_) { } }
    }
};

// Estado vigente de un pallet (última clasificación no anulada) para mostrarlo al escanear. No bloquea si falla.
const estadoVigente = async (poolCalidad, codigo) => {
    try {
        const r = await poolCalidad.request().input('codigo', sql.NVarChar(50), codigo).query(`
            SELECT TOP 1 id, color, clasificado_en
            FROM pallet_clasificaciones
            WHERE pallet_codigo = @codigo AND anulado = 0
            ORDER BY id DESC`);
        const f = r.recordset[0];
        return f ? { id: f.id, color: f.color, clasificadoEn: aHoraPared(f.clasificado_en) } : null;
    } catch (error) {
        console.warn(`No se pudo leer el estado vigente de ${codigo}: ${error.message}`);
        return null;
    }
};

module.exports = {
    COLORES, MAX_PALLETS, interpretarCodigo, aHoraPared, desdeHoraPared,
    SQL_TARJA_FPS, SQL_ETIQUETAS_DEL_REGISTRO,
    consultarTarjaFps, consultarEtiquetasDelRegistro, resolverPallets, insertarClasificaciones, borrarFotosNoUsadas, estadoVigente,
};
