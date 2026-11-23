// Clasificación de pallets INNPACK: consulta de tarja (formularios, sin login) y lectura/anulación (Photino, con auth).
// El guardado de las clasificaciones vive en control.controller.js (misma transacción que la inspección).
const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const {
    COLORES, interpretarCodigo, aHoraPared, consultarTarjaFps, consultarEtiquetasDelRegistro, estadoVigente,
} = require('../utils/clasificacionPallets');

const falla = (res, status, code, message) => res.status(status).json({ ok: false, code, message });

// ---- Consulta de tarja (usada por los formularios al escanear) -----------------------------------------------------
const obtenerTarja = async (req, res) => {
    const info = interpretarCodigo(req.params.codigo);
    if (!info) return falla(res, 400, 'CODIGO_INVALIDO', 'El código no corresponde a una tarja de proceso.');

    let codigo = info.tipo === 'pallet' ? info.codigo : null;

    if (info.tipo === 'registro') {
        let etiquetas;
        try {
            etiquetas = await consultarEtiquetasDelRegistro(info.recordKey);
        } catch (error) {
            console.error('FPS no disponible (etiquetas del registro):', error.message);
            return falla(res, 503, 'FPS_NO_DISPONIBLE', 'No se pudo consultar el sistema de producción. Intente nuevamente.');
        }
        if (etiquetas.length === 0) return falla(res, 404, 'TARJA_NO_ENCONTRADA', 'No se encontró esa tarja.');
        if (etiquetas.length > 1) {
            return res.json({ ok: true, data: { requiereEtiqueta: true, recordKey: info.recordKey, etiquetas } });
        }
        codigo = etiquetas[0].codigo;
    }

    const fps = await consultarTarjaFps(codigo);
    if (fps.estado === 'no_existe') return falla(res, 404, 'TARJA_NO_ENCONTRADA', 'No se encontró esa tarja.');
    if (fps.estado === 'sin_registro') return falla(res, 404, 'TARJA_SIN_REGISTRO_PRODUCCION', 'Esa tarja no corresponde a un proceso de producción.');
    if (fps.estado === 'error') {
        console.error('FPS no disponible (tarja):', fps.error);
        return falla(res, 503, 'FPS_NO_DISPONIBLE', 'No se pudo consultar el sistema de producción. Intente nuevamente.');
    }

    let estadoActual = null;
    try {
        estadoActual = await estadoVigente(await getCalidadSqlServerPool(), codigo);
    } catch (error) {
        console.warn('No se pudo obtener el estado vigente:', error.message);
    }
    return res.json({ ok: true, data: { ...fps.datos, estadoActual } });
};

// ---- Lectura (Photino) ---------------------------------------------------------------------------------------------
// Base común: una fila por clasificación con la marca "vigente" (última no anulada de su pallet) y los datos de la inspección.
const CTE_BASE = `
WITH base AS (
  SELECT c.*, r.usuario_id, r.proceso_id, r.maquina_id, r.np AS np_inspeccion, r.turno, r.area, r.estado_validacion,
         CASE WHEN c.anulado = 0 AND ROW_NUMBER() OVER (
              PARTITION BY c.pallet_codigo ORDER BY CASE WHEN c.anulado = 0 THEN 0 ELSE 1 END, c.id DESC) = 1
              THEN 1 ELSE 0 END AS vigente
  FROM pallet_clasificaciones c
  INNER JOIN registros_control r ON r.id = c.registro_id
)`;

const entero = (v) => { const n = Number(v); return Number.isInteger(n) && n > 0 ? n : null; };
const fecha = (v) => (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null);

// Filtros comunes: desde/hasta (YYYY-MM-DD), color, procesoId, maquinaId, usuarioId (inspector), operador (texto: inspector u operador FPS),
// np, defectoId, palletCodigo, vista=eventos|vigentes (por defecto eventos), incluirAnuladas=1.
const construirFiltros = (q) => {
    const w = [];
    const inputs = [];
    const add = (nombre, tipo, valor) => inputs.push([nombre, tipo, valor]);

    if (q.vista !== 'vigentes' && q.incluirAnuladas !== '1') w.push('b.anulado = 0');
    if (q.vista === 'vigentes') w.push('b.vigente = 1');
    if (fecha(q.desde)) { w.push('b.clasificado_en >= @desde'); add('desde', sql.Date, q.desde); }
    if (fecha(q.hasta)) { w.push('b.clasificado_en < DATEADD(DAY, 1, CAST(@hasta AS DATE))'); add('hasta', sql.Date, q.hasta); }
    if (typeof q.color === 'string' && COLORES.includes(q.color.toUpperCase())) { w.push('b.color = @color'); add('color', sql.NVarChar(5), q.color.toUpperCase()); }
    if (entero(q.procesoId)) { w.push('b.proceso_id = @procesoId'); add('procesoId', sql.Int, entero(q.procesoId)); }
    if (entero(q.maquinaId)) { w.push('b.maquina_id = @maquinaId'); add('maquinaId', sql.Int, entero(q.maquinaId)); }
    if (entero(q.usuarioId)) { w.push('b.usuario_id = @usuarioId'); add('usuarioId', sql.Int, entero(q.usuarioId)); }
    if (typeof q.operador === 'string' && q.operador.trim()) {
        w.push('(u.nombre_completo LIKE @operador OR b.operador_fps LIKE @operador)');
        add('operador', sql.NVarChar(150), `%${q.operador.trim().slice(0, 100)}%`);
    }
    if (typeof q.np === 'string' && q.np.trim()) {
        w.push('(b.np_inspeccion = @np OR b.np_faret = @np OR b.np_innpack = @np OR b.orden_fabricacion = @np)');
        add('np', sql.NVarChar(50), q.np.trim().slice(0, 50));
    }
    if (entero(q.defectoId)) {
        w.push('EXISTS (SELECT 1 FROM pallet_clasificacion_defectos fd WHERE fd.clasificacion_id = b.id AND fd.parametro_id = @defectoId)');
        add('defectoId', sql.Int, entero(q.defectoId));
    }
    if (typeof q.palletCodigo === 'string' && q.palletCodigo.trim()) { w.push('b.pallet_codigo = @palletCodigo'); add('palletCodigo', sql.NVarChar(50), q.palletCodigo.trim().slice(0, 50)); }

    return { where: w.length ? `WHERE ${w.join(' AND ')}` : '', inputs };
};

const JOINS = `
FROM base b
LEFT JOIN usuarios u ON u.id = b.usuario_id
LEFT JOIN procesos p ON p.id = b.proceso_id
LEFT JOIN maquinas m ON m.id = b.maquina_id`;

const pedir = (pool, filtros) => {
    const r = pool.request();
    for (const [n, t, v] of filtros.inputs) r.input(n, t, v);
    return r;
};

const mapear = (f) => ({
    id: f.id,
    registroId: f.registro_id,
    palletCodigo: f.pallet_codigo,
    recordKey: f.record_key,
    nEtiqueta: f.n_etiqueta,
    color: f.color,
    vigente: f.vigente === 1 || f.vigente === true,
    anulado: !!f.anulado,
    anuladoEn: aHoraPared(f.anulado_en),
    anuladoPor: f.anulado_por,
    motivoAnulacion: f.motivo_anulacion,
    observacion: f.observacion,
    fotoUrl: f.foto_ruta,
    clasificadoEn: aHoraPared(f.clasificado_en),
    inspeccion: {
        usuarioId: f.usuario_id, inspector: f.inspector, procesoId: f.proceso_id, proceso: f.proceso, maquinaId: f.maquina_id,
        maquina: f.maquina, np: f.np_inspeccion, turno: f.turno, area: f.area, estadoValidacion: f.estado_validacion,
    },
    fps: {
        verificado: !!f.fps_verificado, ordenFabricacion: f.orden_fabricacion, npFaret: f.np_faret, npInnpack: f.np_innpack,
        cliente: f.cliente, itemNp: f.item_np, codigoProducto: f.codigo_producto, producto: f.producto, proceso: f.proceso_fps,
        maquina: f.maquina_fps, operador: f.operador_fps, fechaTarja: aHoraPared(f.fecha_tarja),
        cantidadUnidades: f.cantidad_unidades === null ? null : Number(f.cantidad_unidades), totalEtiquetas: f.total_etiquetas,
    },
});

const SELECT_FILA = `
SELECT b.*, u.nombre_completo AS inspector, p.nombre AS proceso, m.nombre AS maquina`;

const adjuntarDefectos = async (pool, filas) => {
    if (filas.length === 0) return;
    const ids = filas.map((f) => f.id).filter(Number.isInteger);
    const r = await pool.request().query(`
        SELECT d.clasificacion_id, pv.id, pv.nombre, pv.criticidad
        FROM pallet_clasificacion_defectos d
        INNER JOIN parametros_control_visual pv ON pv.id = d.parametro_id
        WHERE d.clasificacion_id IN (${ids.join(',')})
        ORDER BY pv.nombre`);
    const porClasif = new Map();
    for (const x of r.recordset) {
        if (!porClasif.has(x.clasificacion_id)) porClasif.set(x.clasificacion_id, []);
        porClasif.get(x.clasificacion_id).push({ id: x.id, nombre: x.nombre, criticidad: x.criticidad });
    }
    for (const f of filas) f.defectos = porClasif.get(f.id) || [];
};

const errorServidor = (res, error, contexto) => {
    console.error(`Clasificación de pallets (${contexto}):`, error.message);
    return res.status(500).json({ ok: false, message: 'No se pudo completar la consulta.' });
};

const listarClasificaciones = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const f = construirFiltros(req.query);
        const limite = Math.min(entero(req.query.limite) || 50, 200);
        const pagina = entero(req.query.pagina) || 1;

        const total = await pedir(pool, f).query(`${CTE_BASE} SELECT COUNT(*) AS n ${JOINS} ${f.where}`);
        const r = await pedir(pool, f)
            .input('offset', sql.Int, (pagina - 1) * limite)
            .input('limite', sql.Int, limite)
            .query(`${CTE_BASE} ${SELECT_FILA} ${JOINS} ${f.where} ORDER BY b.id DESC OFFSET @offset ROWS FETCH NEXT @limite ROWS ONLY`);

        const filas = r.recordset.map(mapear);
        await adjuntarDefectos(pool, filas);
        res.json({ ok: true, data: { total: total.recordset[0].n, pagina, limite, items: filas } });
    } catch (error) { errorServidor(res, error, 'listar'); }
};

const SUMA_COLORES = `
  SUM(CASE WHEN b.color = N'AZUL' THEN 1 ELSE 0 END) AS azul,
  SUM(CASE WHEN b.color = N'ROJO' THEN 1 ELSE 0 END) AS rojo,
  SUM(CASE WHEN b.color = N'VERDE' THEN 1 ELSE 0 END) AS verde,
  COUNT(*) AS total`;

const resumenClasificaciones = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const f = construirFiltros(req.query);
        const agrupado = async (columnas, etiqueta) => (await pedir(pool, f).query(
            `${CTE_BASE} SELECT ${columnas}, ${SUMA_COLORES} ${JOINS} ${f.where} GROUP BY ${etiqueta} ORDER BY total DESC`)).recordset;

        const totales = (await pedir(pool, f).query(`${CTE_BASE} SELECT ${SUMA_COLORES} ${JOINS} ${f.where}`)).recordset[0];
        const porProceso = await agrupado('b.proceso_id AS id, p.nombre AS nombre', 'b.proceso_id, p.nombre');
        const porMaquina = await agrupado('b.maquina_id AS id, m.nombre AS nombre', 'b.maquina_id, m.nombre');
        const porDiaRaw = (await pedir(pool, f).query(
            `${CTE_BASE} SELECT CONVERT(VARCHAR(10), b.clasificado_en, 23) AS dia, ${SUMA_COLORES} ${JOINS} ${f.where}
             GROUP BY CONVERT(VARCHAR(10), b.clasificado_en, 23) ORDER BY dia`)).recordset;

        res.json({ ok: true, data: { vista: req.query.vista === 'vigentes' ? 'vigentes' : 'eventos', totales, porProceso, porMaquina, porDia: porDiaRaw } });
    } catch (error) { errorServidor(res, error, 'resumen'); }
};

// Defectos por clasificación: cuántas clasificaciones de cada color tienen cada defecto (+ las que no tienen defectos).
const defectosPorClasificacion = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const f = construirFiltros(req.query);
        const porDefecto = (await pedir(pool, f).query(`
            ${CTE_BASE}
            SELECT b.color, pv.id AS defectoId, pv.nombre, pv.criticidad, COUNT(*) AS cantidad
            ${JOINS}
            INNER JOIN pallet_clasificacion_defectos d ON d.clasificacion_id = b.id
            INNER JOIN parametros_control_visual pv ON pv.id = d.parametro_id
            ${f.where}
            GROUP BY b.color, pv.id, pv.nombre, pv.criticidad
            ORDER BY b.color, cantidad DESC, pv.nombre`)).recordset;
        const sinDefecto = (await pedir(pool, f).query(`
            ${CTE_BASE}
            SELECT b.color, COUNT(*) AS cantidad
            ${JOINS}
            ${f.where ? `${f.where} AND` : 'WHERE'} NOT EXISTS (SELECT 1 FROM pallet_clasificacion_defectos d WHERE d.clasificacion_id = b.id)
            GROUP BY b.color`)).recordset;
        res.json({ ok: true, data: { porDefecto, sinDefecto } });
    } catch (error) { errorServidor(res, error, 'defectos'); }
};

const historialDePallet = async (pool, codigo) => {
    const r = await pool.request().input('codigo', sql.NVarChar(50), codigo)
        .query(`${CTE_BASE} ${SELECT_FILA} ${JOINS} WHERE b.pallet_codigo = @codigo ORDER BY b.id`);
    const filas = r.recordset.map(mapear);
    await adjuntarDefectos(pool, filas);
    return filas;
};

const obtenerClasificacion = async (req, res) => {
    const id = entero(req.params.id);
    if (!id) return falla(res, 400, 'ID_INVALIDO', 'Identificador inválido.');
    try {
        const pool = await getCalidadSqlServerPool();
        const r = await pool.request().input('id', sql.Int, id).query(`${CTE_BASE} SELECT pallet_codigo FROM base WHERE id = @id`);
        if (r.recordset.length === 0) return falla(res, 404, 'NO_ENCONTRADA', 'Clasificación no encontrada.');
        const historial = await historialDePallet(pool, r.recordset[0].pallet_codigo);
        res.json({ ok: true, data: { ...historial.find((h) => h.id === id), historial } });
    } catch (error) { errorServidor(res, error, 'detalle'); }
};

const obtenerHistorial = async (req, res) => {
    const info = interpretarCodigo(req.params.codigo);
    if (!info || info.tipo !== 'pallet') return falla(res, 400, 'CODIGO_INVALIDO', 'Código de pallet inválido.');
    try {
        const pool = await getCalidadSqlServerPool();
        res.json({ ok: true, data: await historialDePallet(pool, info.codigo) });
    } catch (error) { errorServidor(res, error, 'historial'); }
};

// Anulación lógica con motivo (nunca se borra). Solo roles con permiso 'borrar'.
const anularClasificacion = async (req, res) => {
    const id = entero(req.params.id);
    const motivo = typeof req.body?.motivo === 'string' ? req.body.motivo.trim().slice(0, 250) : '';
    if (!id) return falla(res, 400, 'ID_INVALIDO', 'Identificador inválido.');
    if (!motivo) return falla(res, 400, 'MOTIVO_REQUERIDO', 'Debe indicar el motivo de la anulación.');
    try {
        const pool = await getCalidadSqlServerPool();
        const r = await pool.request()
            .input('id', sql.Int, id)
            .input('motivo', sql.NVarChar(250), motivo)
            .input('por', sql.NVarChar(100), (req.auth && (req.auth.nombre || req.auth.usuario)) ? String(req.auth.nombre || req.auth.usuario).slice(0, 100) : null)
            .query(`UPDATE pallet_clasificaciones
                    SET anulado = 1, anulado_en = GETDATE(), anulado_por = @por, motivo_anulacion = @motivo
                    OUTPUT INSERTED.id
                    WHERE id = @id AND anulado = 0`);
        if (r.recordset.length === 0) return falla(res, 404, 'NO_ENCONTRADA_O_YA_ANULADA', 'Clasificación no encontrada o ya anulada.');
        res.json({ ok: true, message: 'Clasificación anulada', data: { id } });
    } catch (error) { errorServidor(res, error, 'anular'); }
};

module.exports = {
    obtenerTarja, listarClasificaciones, resumenClasificaciones, defectosPorClasificacion,
    obtenerClasificacion, obtenerHistorial, anularClasificacion,
    CTE_BASE, construirFiltros,
};
