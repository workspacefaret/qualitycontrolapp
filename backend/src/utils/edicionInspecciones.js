// Edición de inspecciones FARET (Calidad y Pallet/Papel): comparación de campos, motivo obligatorio y bitácora (migración 011).
const { sql } = require('../config/calidadSqlServerPool');

const MOTIVO_MIN = 5;
const MOTIVO_MAX = 500;

class ErrorEdicion extends Error {
    constructor(message, status = 400) { super(message); this.name = 'ErrorEdicion'; this.status = status; }
}

const validarMotivo = (motivo) => {
    const m = typeof motivo === 'string' ? motivo.trim() : '';
    if (m.length < MOTIVO_MIN) throw new ErrorEdicion(`El motivo del cambio es obligatorio (mínimo ${MOTIVO_MIN} caracteres)`);
    if (m.length > MOTIVO_MAX) throw new ErrorEdicion(`El motivo del cambio no puede superar ${MOTIVO_MAX} caracteres`);
    return m;
};

// Texto normalizado para comparar y auditar: null/'' -> null; booleanos -> Sí/No.
const norm = (v) => {
    if (v === undefined || v === null) return null;
    if (typeof v === 'boolean') return v ? 'Sí' : 'No';
    const t = String(v).trim();
    return t === '' ? null : t;
};

// Texto opcional con largo máximo; undefined = "no se envió" (no se modifica).
const textoOpcional = (v, max, nombre) => {
    if (v === undefined) return undefined;
    if (v === null) return null;
    if (typeof v !== 'string') throw new ErrorEdicion(`${nombre} debe ser texto`);
    const t = v.trim();
    if (t.length > max) throw new ErrorEdicion(`${nombre} no puede superar ${max} caracteres`);
    return t === '' ? null : t;
};

const textoObligatorio = (v, max, nombre) => {
    const t = textoOpcional(v, max, nombre);
    if (t === undefined) return undefined;
    if (t === null) throw new ErrorEdicion(`${nombre} es obligatorio`);
    return t;
};

// Usuario que edita (lo fija el middleware de autorización a partir del token; nunca viene del cuerpo).
const actor = (req) => ({
    id: req.auth?.usuario ? String(req.auth.usuario).slice(0, 50) : null,
    nombre: (req.auth?.nombre || req.auth?.usuario || '').toString().slice(0, 150) || null,
    origen: req.auth?.origen || null,
});

// cambios: [{ campo, anterior, nuevo }]
const registrarAuditoria = async (transaction, { tipo, registroId, cambios, motivo, usuario }) => {
    for (const c of cambios) {
        await new sql.Request(transaction)
            .input('tipo', sql.NVarChar(10), tipo)
            .input('registroId', sql.Int, registroId)
            .input('campo', sql.NVarChar(200), c.campo)
            .input('anterior', sql.NVarChar(sql.MAX), c.anterior)
            .input('nuevo', sql.NVarChar(sql.MAX), c.nuevo)
            .input('motivo', sql.NVarChar(500), motivo)
            .input('usuarioId', sql.NVarChar(50), usuario.id)
            .input('usuarioNombre', sql.NVarChar(150), usuario.nombre)
            .input('origen', sql.NVarChar(20), usuario.origen)
            .query(`INSERT INTO dbo.inspecciones_faret_auditoria
                    (tipo, registro_id, campo, valor_anterior, valor_nuevo, motivo, usuario_id, usuario_nombre, origen)
                    VALUES (@tipo, @registroId, @campo, @anterior, @nuevo, @motivo, @usuarioId, @usuarioNombre, @origen)`);
    }
};

const listarAuditoria = async (pool, tipo, registroId) => {
    const r = await pool.request()
        .input('tipo', sql.NVarChar(10), tipo)
        .input('id', sql.Int, registroId)
        .query(`SELECT id, campo, valor_anterior AS valorAnterior, valor_nuevo AS valorNuevo, motivo,
                       usuario_id AS usuarioId, usuario_nombre AS usuarioNombre, origen, fecha
                FROM dbo.inspecciones_faret_auditoria WHERE tipo = @tipo AND registro_id = @id ORDER BY id DESC`);
    return r.recordset;
};

// ¿Existe la bitácora? (si el backend se despliega antes de la 011, los listados siguen funcionando sin el dato de edición)
let cacheAud = { hasta: 0, ok: false };
const auditoriaDisponible = async (pool, ahora = Date.now()) => {
    if (ahora < cacheAud.hasta) return cacheAud.ok;
    let ok = false;
    try {
        const r = await pool.request().query(`SELECT OBJECT_ID(N'dbo.inspecciones_faret_auditoria', N'U') AS id`);
        ok = !!r.recordset[0]?.id;
    } catch (_) { ok = false; }
    cacheAud = { hasta: ahora + 30000, ok };
    return ok;
};
const _vaciarCacheAuditoria = () => { cacheAud = { hasta: 0, ok: false }; };

// Fragmento SELECT con el resumen de ediciones de un registro (alias r = tabla del registro).
const resumenEdicionSql = (tipo) => `,
              (SELECT COUNT(DISTINCT au.fecha) FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'${tipo}' AND au.registro_id = r.id) AS cantidadEdiciones,
              (SELECT TOP 1 au.fecha FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'${tipo}' AND au.registro_id = r.id ORDER BY au.id DESC) AS ultimaEdicionFecha,
              (SELECT TOP 1 au.usuario_nombre FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'${tipo}' AND au.registro_id = r.id ORDER BY au.id DESC) AS ultimaEdicionUsuario,
              (SELECT TOP 1 au.motivo FROM dbo.inspecciones_faret_auditoria au WHERE au.tipo = N'${tipo}' AND au.registro_id = r.id ORDER BY au.id DESC) AS ultimaEdicionMotivo`;

module.exports = {
    ErrorEdicion, validarMotivo, norm, textoOpcional, textoObligatorio, actor, registrarAuditoria, listarAuditoria,
    auditoriaDisponible, resumenEdicionSql, _vaciarCacheAuditoria, MOTIVO_MIN, MOTIVO_MAX,
};
