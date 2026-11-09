// Catálogo maestro de eventos de Calidad FARET (migración 010): consulta y resolución de defectos.
// - La criticidad y el texto SIEMPRE salen de SQL Server (vista vw_calidad_faret_eventos_operables); lo que mande el cliente se ignora.
// - Los defectos "legados" (strings) siguen aceptándose según CALIDAD_FARET_EVENTOS_LEGACY = off | observar (defecto) | exigir.
const crypto = require('crypto');
const { sql } = require('../config/calidadSqlServerPool');

const ID_EVENTO = /^[A-Z]{3}-\d{3}$/;
const MAX_DEFECTOS = 100;
const MAX_TEXTO = 150;            // largo de registro_calidad_faret_defectos.defecto
const CACHE_MS = 30 * 1000;       // el catálogo cambia muy rara vez; la validación del POST NO usa esta caché
const AVISO_CADA_MS = 10 * 60 * 1000;

class ErrorValidacion extends Error {
    constructor(message, status = 400) { super(message); this.name = 'ErrorValidacion'; this.status = status; }
}

const modoLegado = () => {
    const v = String(process.env.CALIDAD_FARET_EVENTOS_LEGACY || 'observar').trim().toLowerCase();
    return ['off', 'observar', 'exigir'].includes(v) ? v : 'observar';
};

// Aviso agrupado (no una línea por solicitud) y sin contenido de la inspección.
let legadosPendientes = 0;
let ultimoAviso = 0;
const avisarLegado = (cantidad, ahora = Date.now()) => {
    legadosPendientes += cantidad;
    if (ahora - ultimoAviso >= AVISO_CADA_MS) {
        console.warn(`[calidad-faret] defectos enviados como texto (cliente sin catálogo): ${legadosPendientes} desde el último aviso`);
        legadosPendientes = 0;
        ultimoAviso = ahora;
    }
};
const _reiniciarAvisos = () => { legadosPendientes = 0; ultimoAviso = 0; };

const SQL_AREAS = `SELECT cod_area, nombre, area_control, orden FROM dbo.calidad_faret_areas WHERE estado = N'Activo' ORDER BY orden, cod_area`;
const SQL_EVENTOS = `SELECT id_evento, cod_area, defecto, criticidad, orden_evento FROM dbo.vw_calidad_faret_eventos_operables ORDER BY orden_area, orden_evento, id_evento`;

const construirCatalogo = (areasRows, eventosRows) => {
    const areas = areasRows.map((a) => ({
        codArea: a.cod_area,
        areaControl: a.area_control,
        nombre: a.nombre,
        orden: a.orden,
        eventos: [],
    }));
    const porCodigo = new Map(areas.map((a) => [a.codArea, a]));
    for (const e of eventosRows) {
        const area = porCodigo.get(e.cod_area);
        if (area) area.eventos.push({ idEvento: e.id_evento, defecto: e.defecto, criticidad: e.criticidad, orden: e.orden_evento });
    }
    const cuerpo = { areas, totales: { areas: areas.length, eventos: areas.reduce((n, a) => n + a.eventos.length, 0) } };
    const version = crypto.createHash('sha256').update(JSON.stringify(cuerpo)).digest('hex').slice(0, 16);
    return { version, ...cuerpo };
};

let cache = { hasta: 0, valor: null };
const _vaciarCache = () => { cache = { hasta: 0, valor: null }; };

const obtenerCatalogo = async (pool, ahora = Date.now()) => {
    if (cache.valor && ahora < cache.hasta) return cache.valor;
    const [areas, eventos] = await Promise.all([
        pool.request().query(SQL_AREAS),
        pool.request().query(SQL_EVENTOS),
    ]);
    const valor = construirCatalogo(areas.recordset, eventos.recordset);
    cache = { hasta: ahora + CACHE_MS, valor };
    return valor;
};

const esErrorCatalogoNoDisponible = (error) => error && (error.number === 208 || error.number === 229 || error.number === 262);

/**
 * Clasifica y valida `defectos` y resuelve los eventos contra SQL Server.
 * Devuelve [{ texto, idEvento|null, criticidad|null }]. Lanza ErrorValidacion (400) ante datos inválidos.
 * `pool` solo se consulta si hay eventos {idEvento}; un cuerpo 100% legado no toca el catálogo.
 */
const resolverDefectos = async (pool, defectos, areaDefecto) => {
    if (defectos === undefined || defectos === null) return [];
    if (!Array.isArray(defectos)) throw new ErrorValidacion('defectos debe ser una lista');
    if (defectos.length > MAX_DEFECTOS) throw new ErrorValidacion('Demasiados defectos en la inspección');

    const textos = [];
    const ids = [];
    for (const d of defectos) {
        if (typeof d === 'string') {
            const t = d.trim();
            if (!t) throw new ErrorValidacion('Defecto vacío');
            if (t.length > MAX_TEXTO) throw new ErrorValidacion('Texto de defecto demasiado largo');
            textos.push(t);
        } else if (d && typeof d === 'object' && !Array.isArray(d)) {
            const id = typeof d.idEvento === 'string' ? d.idEvento.trim().toUpperCase() : '';
            if (!ID_EVENTO.test(id)) throw new ErrorValidacion('idEvento inválido');
            if (!ids.includes(id)) ids.push(id);      // duplicados: se registra una sola vez
        } else {
            throw new ErrorValidacion('Defecto con formato no válido');
        }
    }

    const modo = modoLegado();
    if (textos.length > 0) {
        if (modo === 'exigir') throw new ErrorValidacion('Actualice la aplicación: los defectos deben enviarse con idEvento del catálogo');
        if (modo === 'observar') avisarLegado(textos.length);
    }

    const resueltos = [];
    if (ids.length > 0) {
        if (!areaDefecto) throw new ErrorValidacion('areaDefecto es obligatorio cuando se informan eventos del catálogo');
        let rows;
        try {
            const req = pool.request();
            ids.forEach((id, i) => req.input(`e${i}`, sql.NVarChar(10), id));
            const lista = ids.map((_, i) => `@e${i}`).join(', ');
            const r = await req.query(`SELECT id_evento, area_control, defecto, criticidad FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento IN (${lista})`);
            rows = r.recordset;
        } catch (error) {
            if (esErrorCatalogoNoDisponible(error)) throw new ErrorValidacion('Catálogo de eventos no disponible', 503);
            throw error;
        }
        const porId = new Map(rows.map((r) => [r.id_evento, r]));
        for (const id of ids) {
            const ev = porId.get(id);
            if (!ev) throw new ErrorValidacion(`Evento ${id} inexistente o no disponible`);
            if (ev.area_control !== areaDefecto) throw new ErrorValidacion(`Evento ${id} no corresponde al área ${areaDefecto}`);
            resueltos.push({ texto: ev.defecto, idEvento: ev.id_evento, criticidad: ev.criticidad });
        }
    }
    return [...textos.map((t) => ({ texto: t, idEvento: null, criticidad: null })), ...resueltos];
};

// Errores lanzados por los triggers de la 010 (carrera: el evento se dio de baja o se cambió de área entre la validación y el INSERT).
const esErrorTriggerEvento = (error) => error && (error.number === 51030 || error.number === 51031 || error.number === 51032);

module.exports = {
    ErrorValidacion, resolverDefectos, obtenerCatalogo, construirCatalogo, esErrorTriggerEvento, modoLegado,
    SQL_AREAS, SQL_EVENTOS, _vaciarCache, _reiniciarAvisos,
};
