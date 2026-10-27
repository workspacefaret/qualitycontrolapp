// Autorización de operaciones sensibles (consulta de registros/evidencias y borrado) reutilizando los JWT existentes:
//  - QualityControlFaret.Api (sesiones FARET):      GET {FARET}/api/Auth/me             -> roles vigentes desde su BD
//  - QualityControl INNPACK Api (sesiones INNPACK): GET {INNPACK}/api/Auth/mis-permisos -> solo valida el token; el rol sale
//    del mismo token (ya validado por la API emisora, por lo que sus claims son confiables hasta su vencimiento)
// Los formularios de inspección (POST, catálogos, contexto QR) NO usan este middleware: siguen anónimos.
// Modos por operación (variables de entorno): off | observar (registra y deja pasar) | exigir (401/403/503).
const crypto = require('crypto');

const URL_FARET = (process.env.AUTH_FARET_URL || 'https://api.faret.cl/qualitycontrol').replace(/\/+$/, '');
const URL_INNPACK = (process.env.AUTH_INNPACK_URL || 'https://api.faret.cl/innpack').replace(/\/+$/, '');
const TIMEOUT_MS = parseInt(process.env.AUTH_TIMEOUT_MS, 10) || 4000;
const TTL_OK_MS = Math.min(parseInt(process.env.AUTH_CACHE_SEG, 10) || 60, 300) * 1000;
const TTL_FALLO_MS = 15 * 1000;
const MAX_CACHE = 500;

// Los nombres de rol difieren entre APIs (ADMIN/CALIDAD/INSPECTOR/CONSULTA en Faret; admin/admin_ti/calidad/inspector/consulta
// en INNPACK): se normalizan a mayúsculas. Borrar = misma regla que el gateway QCC Web (admin, admin_ti, calidad).
const PERMISOS = {
    // OPERADOR: rol de las sesiones INNPACK del Desktop/Web (ROLES_INNPACK = admin, admin_ti, operador); ya ven estos registros hoy.
    leer: new Set(['ADMIN', 'ADMIN_TI', 'CALIDAD', 'INSPECTOR', 'CONSULTA', 'OPERADOR']),
    borrar: new Set(['ADMIN', 'ADMIN_TI', 'CALIDAD']),
};

const modo = (nombre) => {
    const v = String(process.env[nombre] || 'observar').toLowerCase();
    return ['off', 'observar', 'exigir'].includes(v) ? v : 'observar';
};

const cache = new Map();
const hash = (t) => crypto.createHash('sha256').update(t).digest('hex');

const decodificar = (token) => {
    try {
        const partes = token.split('.');
        if (partes.length !== 3) return null;
        return JSON.parse(Buffer.from(partes[1], 'base64url').toString('utf8'));
    } catch (_) { return null; }
};

const rolesDeClaims = (claims) => {
    const crudos = [];
    for (const k of ['role', 'rol', 'roles', 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role']) {
        const v = claims[k];
        if (Array.isArray(v)) crudos.push(...v); else if (v) crudos.push(v);
    }
    return crudos.map((r) => String(r).toUpperCase());
};

const llamar = async (url, token) => {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    try {
        const r = await fetch(url, { headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' }, signal: ctrl.signal, redirect: 'manual' });
        return { status: r.status, cuerpo: r.status === 200 ? await r.json().catch(() => null) : null };
    } finally { clearTimeout(timer); }
};

// -> { estado: 'ok'|'invalido'|'error', usuario, roles:Set, origen }
const validarToken = async (token) => {
    const claims = decodificar(token);
    if (!claims) return { estado: 'invalido' };
    if (claims.exp && claims.exp * 1000 < Date.now()) return { estado: 'invalido', motivo: 'expirado' };

    const k = hash(token);
    const previo = cache.get(k);
    if (previo && previo.vence > Date.now()) return previo.valor;

    let valor = { estado: 'invalido' };
    try {
        const faret = await llamar(`${URL_FARET}/api/Auth/me`, token);
        if (faret.status === 200 && faret.cuerpo) {
            const u = faret.cuerpo.data || faret.cuerpo;
            valor = { estado: 'ok', origen: 'faret', usuario: String(u.id ?? claims.sub ?? ''), roles: new Set((u.roles || []).map((r) => String(r).toUpperCase())) };
        } else if (faret.status >= 500) {
            valor = { estado: 'error' };
        } else {
            const inn = await llamar(`${URL_INNPACK}/api/Auth/mis-permisos`, token);
            if (inn.status === 200) valor = { estado: 'ok', origen: 'innpack', usuario: String(claims.sub ?? claims.nameid ?? ''), roles: new Set(rolesDeClaims(claims)) };
            else if (inn.status >= 500) valor = { estado: 'error' };
        }
    } catch (_) { valor = { estado: 'error' }; }

    if (valor.estado !== 'error') {
        if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value);
        // Nunca más allá del vencimiento del propio token.
        const tope = claims.exp ? claims.exp * 1000 : Infinity;
        cache.set(k, { valor, vence: Math.min(Date.now() + (valor.estado === 'ok' ? TTL_OK_MS : TTL_FALLO_MS), tope) });
    }
    return valor;
};

const auditar = (req, evento, extra = {}) => {
    // Sin tokens ni cabeceras: solo evento, método, ruta base e identificador de usuario.
    console.log(JSON.stringify({ t: new Date().toISOString(), evento, metodo: req.method, ruta: req.baseUrl + req.path.replace(/\/\d+/g, '/:id'), ip: req.ip, ...extra }));
};

// permiso: 'leer' | 'borrar'; nombreModo: variable de entorno que fija off/observar/exigir para esa operación.
const autorizar = (permiso, nombreModo) => async (req, res, next) => {
    const m = modo(nombreModo);
    if (m === 'off') return next();

    const rechazar = (status, mensaje, evento, extra) => {
        auditar(req, evento, { modo: m, ...extra });
        if (m === 'observar') return next();
        return res.status(status).json({ ok: false, message: mensaje });
    };

    const cab = req.headers.authorization || '';
    const token = /^Bearer\s+(\S+)$/i.exec(cab)?.[1];
    if (!token) return rechazar(401, 'Autenticación requerida.', 'auth_sin_token');

    const r = await validarToken(token);
    if (r.estado === 'error') return rechazar(503, 'No fue posible validar la sesión. Intente nuevamente.', 'auth_upstream_error');
    if (r.estado !== 'ok') return rechazar(401, 'Sesión inválida o expirada.', 'auth_token_invalido', { motivo: r.motivo });

    const permitidos = PERMISOS[permiso];
    if (![...r.roles].some((x) => permitidos.has(x))) return rechazar(403, 'No tiene permisos para esta operación.', 'auth_sin_permiso', { usuario: r.usuario, origen: r.origen });

    req.auth = { usuario: r.usuario, roles: r.roles, origen: r.origen };
    if (permiso === 'borrar') auditar(req, 'auth_borrado_autorizado', { usuario: r.usuario, origen: r.origen });
    return next();
};

const _limpiarCache = () => cache.clear();

module.exports = { autorizar, validarToken, modo, _limpiarCache };
