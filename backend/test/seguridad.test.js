// Autorización por JWT (Faret/INNPACK), URLs firmadas de /uploads, límites de 25 MB y envíos anónimos.
// Las APIs de autenticación se reemplazan por un servidor local de prueba (no se contacta ningún servicio real).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const Module = require('module');

// ---- APIs de autenticación de prueba -----------------------------------------------------------
const llamadasAuth = { faret: 0, innpack: 0 };
const usuarios = {
    F_ADMIN: { api: 'faret', roles: ['ADMIN'] },
    F_CALIDAD: { api: 'faret', roles: ['CALIDAD'] },
    F_CONSULTA: { api: 'faret', roles: ['CONSULTA'] },
    F_SINROL: { api: 'faret', roles: ['OTRO'] },
    I_CALIDAD: { api: 'innpack', roles: ['calidad'] },
    I_ADMINTI: { api: 'innpack', roles: ['admin_ti'] },
    I_CONSULTA: { api: 'innpack', roles: ['consulta'] },
    I_OPERADOR: { api: 'innpack', roles: ['operador'] },
};
const upstream = http.createServer((req, res) => {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    let claims = {};
    try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()); } catch (_) { }
    const u = usuarios[claims.sub];
    const json = (st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (claims.sub === 'CAIDO') return json(500, {});
    if (req.url === '/faret/api/Auth/me') { llamadasAuth.faret++; return u && u.api === 'faret' ? json(200, { success: true, data: { id: 7, roles: u.roles } }) : json(401, {}); }
    if (req.url === '/innpack/api/Auth/mis-permisos') { llamadasAuth.innpack++; return u && u.api === 'innpack' ? json(200, []) : json(401, {}); }
    return json(404, {});
});

const jwt = (sub, expOffsetSeg = 3600, extra = {}) => {
    const b = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const claims = { sub, exp: Math.floor(Date.now() / 1000) + expOffsetSeg, ...extra };
    if (usuarios[sub] && usuarios[sub].api === 'innpack') claims.role = usuarios[sub].roles[0];
    return `${b({ alg: 'HS256' })}.${b(claims)}.firma`;
};

// ---- doble de SQL Server -----------------------------------------------------------------------
const RUTA_FOTO = '/uploads/calidad_faret/prueba-seguridad.jpg';
const borrados = [];
const inserts = { faret: 0, control: 0, pt: 0 };
class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        const t = text.replace(/\s+/g, ' ');
        if (/FROM registro_calidad_faret_adjuntos/.test(t)) return { recordset: [{ id: 1, nombreOriginal: 'a.jpg', rutaArchivo: RUTA_FOTO, mimeType: 'image/jpeg' }] };
        if (/UPDATE registros_calidad_faret SET eliminado/.test(t)) { borrados.push(this.p.id); return { rowsAffected: [1] }; }
        if (/SELECT id FROM registros_.* WHERE client_uuid/.test(t)) return { recordset: [] };
        if (/INSERT INTO registros_calidad_faret\b/.test(t)) { inserts.faret++; return { recordset: [{ id: 501 }] }; }
        if (/INSERT INTO registros_control/.test(t)) { inserts.control++; return { recordset: [{ id: 601 }] }; }
        if (/INSERT INTO registros_producto_terminado/.test(t)) { inserts.pt++; return { recordset: [{ id: 701 }] }; }
        if (/INSERT INTO registro_pt_hallazgos/.test(t)) return { recordset: [{ id: 1 }] };
        return { recordset: [] };
    }
}
const sqlStub = new Proxy({}, { get: (_, k) => (k === 'Transaction' ? class { async begin() { } async commit() { } async rollback() { } } : k === 'Request' ? FakeRequest : () => 'T') });
const cargar = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    return cargar.call(this, request, ...rest);
};

process.env.UPLOADS_SECRET = 'secreto-de-prueba';
process.env.UPLOADS_BASE_PUBLICA = 'http://127.0.0.1';
process.env.LIMITE_POST_POR_MIN = '0';

const express = require('express');
let app; let server; let base; let authServer;
const dirFaret = path.resolve(__dirname, '../uploads/calidad_faret');
const dirControl = path.resolve(__dirname, '../uploads/control');
const FOTO_FISICA = path.join(dirFaret, 'prueba-seguridad.jpg');
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), crypto.randomBytes(4000)]);

test.before(async () => {
    await new Promise((r) => upstream.listen(0, '127.0.0.1', r));
    authServer = `http://127.0.0.1:${upstream.address().port}`;
    process.env.AUTH_FARET_URL = `${authServer}/faret`;
    process.env.AUTH_INNPACK_URL = `${authServer}/innpack`;
    process.env.AUTH_CONSULTAS_MODO = 'exigir';
    process.env.AUTH_BORRADO_MODO = 'exigir';
    process.env.UPLOADS_MODO = 'exigir';

    fs.mkdirSync(dirFaret, { recursive: true });
    fs.writeFileSync(FOTO_FISICA, JPEG);

    app = express();
    app.set('trust proxy', 'loopback');
    app.use(express.json());
    app.use('/api/adjuntos', require('../src/routes/adjuntos.routes'));
    app.use('/api/control', require('../src/routes/control.routes'));
    app.use('/api/calidad-faret', require('../src/routes/calidadFaret.routes'));
    app.use('/api/calidad-faret-pallet', require('../src/routes/calidadFaretPallet.routes'));
    app.use('/api/producto-terminado', require('../src/routes/productoTerminado.routes'));
    app.use('/uploads', require('../src/middleware/uploadsAcceso').uploadsAcceso, express.static(path.resolve(__dirname, '../uploads'), { index: false, dotfiles: 'ignore' }));
    server = http.createServer(app);
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => {
    server.close(); upstream.close();
    try { fs.unlinkSync(FOTO_FISICA); } catch (_) { }
});
test.beforeEach(() => require('../src/middleware/auth')._limpiarCache());

const get = (ruta, token) => fetch(base + ruta, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
const del = (ruta, token) => fetch(base + ruta, { method: 'DELETE', headers: token ? { Authorization: `Bearer ${token}` } : {} });

// ---- consulta (modo exigir) --------------------------------------------------------------------
test('consulta sin token: 401; con token de sesión FARET válida: 200', async () => {
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos')).status, 401);
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('F_CONSULTA'))).status, 200);
});

test('consulta con sesión INNPACK válida (token distinto de Faret): 200', async () => {
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('I_CONSULTA'))).status, 200);
});

test('token expirado, malformado o revocado: 401; usuario sin rol de lectura: 403', async () => {
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('F_ADMIN', -60))).status, 401);
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', 'basura')).status, 401);
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt("REVOCADO"))).status, 401);
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('F_SINROL'))).status, 403);
});

test('rol operador de INNPACK: puede consultar (como hoy en Desktop/Web) pero no borrar', async () => {
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('I_OPERADOR'))).status, 200);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('I_OPERADOR'))).status, 403);
});

test('API de autenticación caída: falla cerrado (503), no concede acceso', async () => {
    assert.strictEqual((await get('/api/calidad-faret/registros/1/adjuntos', jwt('CAIDO'))).status, 503);
});

test('la validación se cachea unos segundos (no consulta a la API en cada petición)', async () => {
    const t = jwt('F_ADMIN'); const antes = llamadasAuth.faret;
    await get('/api/calidad-faret/registros/1/adjuntos', t); await get('/api/calidad-faret/registros/1/adjuntos', t);
    assert.strictEqual(llamadasAuth.faret - antes, 1);
});

// ---- borrado ------------------------------------------------------------------------------------
test('borrado: sin token 401, solo lectura 403, ADMIN/CALIDAD/admin_ti autorizados (Faret y pallet)', async () => {
    borrados.length = 0;
    assert.strictEqual((await del('/api/calidad-faret/registros/9')).status, 401);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('F_CONSULTA'))).status, 403);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('I_CONSULTA'))).status, 403);
    assert.strictEqual((await del('/api/calidad-faret-pallet/registros/9', jwt('F_CONSULTA'))).status, 403);
    assert.deepStrictEqual(borrados, []);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('F_CALIDAD'))).status, 200);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('F_ADMIN'))).status, 200);
    assert.strictEqual((await del('/api/calidad-faret/registros/9', jwt('I_ADMINTI'))).status, 200);
    assert.strictEqual(borrados.length, 3);
});

test('consultas de pallet y producto terminado también exigen sesión', async () => {
    for (const r of ['/api/calidad-faret-pallet/registros', '/api/calidad-faret-pallet/registros/1', '/api/producto-terminado/registros', '/api/producto-terminado/registros/1', '/api/calidad-faret/registros', '/api/calidad-faret/resumen']) {
        assert.strictEqual((await get(r)).status, 401, r);
    }
});

// ---- modos observar / off ---------------------------------------------------------------------
test('modo observar: deja pasar sin token (clientes antiguos) y NO firma URLs; con token sí', async () => {
    process.env.AUTH_CONSULTAS_MODO = 'observar'; process.env.AUTH_BORRADO_MODO = 'observar';
    try {
        const anonimo = await (await get('/api/calidad-faret/registros/1/adjuntos')).json();
        assert.strictEqual(anonimo.data[0].rutaArchivo, RUTA_FOTO);
        const conToken = await (await get('/api/calidad-faret/registros/1/adjuntos', jwt('F_CONSULTA'))).json();
        assert.match(conToken.data[0].rutaArchivo, /^http:\/\/127\.0\.0\.1\/uploads\/calidad_faret\/prueba-seguridad\.jpg\?exp=\d+&sig=/);
        assert.strictEqual((await del('/api/calidad-faret/registros/9')).status, 200);
    } finally { process.env.AUTH_CONSULTAS_MODO = 'exigir'; process.env.AUTH_BORRADO_MODO = 'exigir'; }
});

// ---- URLs firmadas ------------------------------------------------------------------------------
const firmada = async () => {
    const j = await (await get('/api/calidad-faret/registros/1/adjuntos', jwt('F_CONSULTA'))).json();
    return new URL(j.data[0].rutaArchivo);
};

test('la respuesta autenticada trae URL firmada que descarga la foto ORIGINAL sin alterar (sin re-encode)', async () => {
    const u = await firmada();
    const r = await get(u.pathname + u.search);
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.headers.get('x-content-type-options'), 'nosniff');
    assert.ok(Buffer.from(await r.arrayBuffer()).equals(JPEG));
});

test('/uploads sin firma en modo exigir: 401; en observar: se sirve (histórico compatible)', async () => {
    assert.strictEqual((await get(RUTA_FOTO)).status, 401);
    process.env.UPLOADS_MODO = 'observar';
    try { assert.strictEqual((await get(RUTA_FOTO)).status, 200); } finally { process.env.UPLOADS_MODO = 'exigir'; }
});

test('firma manipulada, de otro archivo o vencida: 403', async () => {
    const u = await firmada();
    const exp = u.searchParams.get('exp'); const sig = u.searchParams.get('sig');
    assert.strictEqual((await get(`${u.pathname}?exp=${exp}&sig=${sig.slice(0, -2)}AA`)).status, 403);
    assert.strictEqual((await get(`${u.pathname}?exp=${Number(exp) + 3600}&sig=${sig}`)).status, 403);
    assert.strictEqual((await get(`/uploads/calidad_faret/otro.jpg?exp=${exp}&sig=${sig}`)).status, 403);
    const vencida = crypto.createHmac('sha256', 'secreto-de-prueba').update(`${RUTA_FOTO}|1000`).digest('base64url');
    assert.strictEqual((await get(`${RUTA_FOTO}?exp=1000&sig=${vencida}`)).status, 403);
    assert.strictEqual((await get(`${RUTA_FOTO}?sig=${sig}`)).status, 403);
});

test('traversal y archivos activos: 404 aunque se intente firmar', async () => {
    const t = jwt('F_CONSULTA');
    for (const r of ['../../server.js', '..%2F..%2Fserver.js', 'calidad_faret/../../server.js', 'control/x.html', 'control/x.svg', '/etc/passwd', 'otra/x.jpg']) {
        assert.strictEqual((await get(`/api/adjuntos/firmar?ruta=${encodeURIComponent(r)}`, t)).status, 404, r);
    }
    assert.strictEqual((await get('/uploads/..%2f..%2fserver.js?exp=1&sig=x')).status, 404);
    assert.strictEqual((await get('/uploads/calidad_faret/x.html')).status, 404);
});

test('/api/adjuntos/firmar: sin sesión 401; con sesión INNPACK y foto histórica existente emite URL válida', async () => {
    assert.strictEqual((await get(`/api/adjuntos/firmar?ruta=${RUTA_FOTO}`)).status, 401);
    const r = await get(`/api/adjuntos/firmar?ruta=${RUTA_FOTO}`, jwt('I_CONSULTA'));
    assert.strictEqual(r.status, 200);
    const j = await r.json();
    const u = new URL(j.data.url);
    assert.strictEqual((await get(u.pathname + u.search)).status, 200);
    assert.strictEqual((await get(`/api/adjuntos/firmar?ruta=/uploads/calidad_faret/no-existe.jpg`, jwt('I_CONSULTA'))).status, 404);
    // acepta la ruta tal como la devuelven las APIs externas (con prefijo /calidad)
    assert.strictEqual((await get(`/api/adjuntos/firmar?ruta=${encodeURIComponent('https://api.faret.cl/calidad' + RUTA_FOTO)}`, jwt('I_CONSULTA'))).status, 200);
});

// ---- envíos anónimos y límites ---------------------------------------------------------------
const form = (campos, archivos, nombreCampo) => {
    const fd = new FormData();
    for (const [k, v] of Object.entries(campos)) fd.append(k, v);
    for (const [n, buf] of archivos) fd.append(nombreCampo, new Blob([buf]), n);
    return fd;
};
const faretPayload = { nvFaret: 'NV1', nvVoBoAprobado: true, areaControl: '03-OFFSET', operador: 'ANDRES', maquina: 'M1', presentaDefectos: false };
const jpegDe = (bytes) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(bytes - 4, 7)]);
const MB = 1024 * 1024;
const nuevosFaret = new Set();
const dirPt = path.resolve(__dirname, '../uploads/producto_terminado');
const limpiar = () => { for (const d of [dirFaret, dirControl, dirPt]) for (const f of fs.readdirSync(d)) if (fs.existsSync(path.join(d, f)) && /^\d+-\d+\.(jpg|upload)$/.test(f) && fs.statSync(path.join(d, f)).mtimeMs > Date.now() - 60000) { try { fs.unlinkSync(path.join(d, f)); } catch (_) { } } };
test.afterEach(limpiar);

test('formularios anónimos con TODOS los modos en exigir: Faret, INNPACK y Producto Terminado guardan sin token', async () => {
    const f1 = await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, [['a.jpg', jpegDe(5000)]], 'archivos') });
    assert.strictEqual(f1.status, 201);
    const c = await fetch(`${base}/api/control/registros`, { method: 'POST', body: form({ payload: JSON.stringify({ usuarioId: 1, procesoId: 3, maquinaId: 6, formularioId: 1, turno: 'A', resultadoVisual: 'Conforme', tipoControl: 'CALIDAD' }) }, [['f.jpg', jpegDe(5000)]], 'archivo') });
    assert.ok([200, 201, 400].includes(c.status), 'control responde sin pedir sesión: ' + c.status);
    assert.notStrictEqual(c.status, 401);
    const pt = await fetch(`${base}/api/producto-terminado/registros`, { method: 'POST', body: form({ payload: JSON.stringify({ usuarioId: 1, procesoPt: 'Pegado', empresa: 'X', cantidadLote: 10, turno: 'A', nivelInspeccion: 'II', aql: 1, letraCodigo: 'F', tamanoMuestra: 5, resultado: 'CONFORME', hallazgos: [{ origenId: 1, defectoIds: [] }] }) }, [['x.jpg', jpegDe(5000)]], 'fotos') });
    assert.strictEqual(pt.status, 201);
});

test('foto de 25 MB exactos se acepta y se guarda sin modificar; resolución/bytes originales intactos', async () => {
    const grande = jpegDe(25 * MB);
    const r = await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, [['grande.jpg', grande]], 'archivos') });
    assert.strictEqual(r.status, 201);
    const guardado = fs.readdirSync(dirFaret).filter((f) => /^\d+-\d+\.jpg$/.test(f)).map((f) => path.join(dirFaret, f)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
    assert.ok(Buffer.compare(fs.readFileSync(guardado), grande) === 0);
});

test('foto de 25 MB + 1 byte se rechaza con 413 y no deja residuos', async () => {
    const antes = fs.readdirSync(dirFaret).length;
    const r = await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, [['x.jpg', jpegDe(25 * MB + 1)]], 'archivos') });
    assert.strictEqual(r.status, 413);
    assert.match((await r.json()).message, /25 MB/);
    await new Promise((x) => setTimeout(x, 200));
    assert.strictEqual(fs.readdirSync(dirFaret).length, antes);
});

test('varias fotos grandes en una inspección (3 x 20 MB) se aceptan; la sexta foto se rechaza', async () => {
    const tres = [['a.jpg', jpegDe(20 * MB)], ['b.jpg', jpegDe(20 * MB)], ['c.jpg', jpegDe(20 * MB)]];
    assert.strictEqual((await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, tres, 'archivos') })).status, 201);
    const seis = Array.from({ length: 6 }, (_, i) => [`${i}.jpg`, jpegDe(2000)]);
    assert.strictEqual((await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, seis, 'archivos') })).status, 400);
});

test('petición cuyo tamaño declarado excede el total permitido se corta antes de leer el cuerpo (413)', async () => {
    const r = await new Promise((resolve) => {
        const req = http.request(`${base}/api/control/registros`, { method: 'POST', headers: { 'content-type': 'multipart/form-data; boundary=x', 'content-length': String(500 * MB) } }, (res) => { res.resume(); resolve(res.statusCode); });
        req.on('error', () => resolve('error')); req.end();
    });
    assert.strictEqual(r, 413);
});

test('Producto Terminado: más de 40 fotos se rechaza', async () => {
    const muchas = Array.from({ length: 41 }, (_, i) => [`${i}.jpg`, jpegDe(1000)]);
    const r = await fetch(`${base}/api/producto-terminado/registros`, { method: 'POST', body: form({ payload: JSON.stringify({ hallazgos: [] }) }, muchas, 'fotos') });
    assert.strictEqual(r.status, 400);
});

test('cliente antiguo: envío sin clientId y sin Authorization sigue funcionando', async () => {
    const r = await fetch(`${base}/api/calidad-faret/registros`, { method: 'POST', body: form({ payload: JSON.stringify(faretPayload) }, [], 'archivos') });
    assert.strictEqual(r.status, 201);
});

test('limitador de envíos: tras superar el umbral por IP responde 429; los GET públicos no cuentan', async () => {
    const { limitarSolicitudes, _reiniciar } = require('../src/middleware/limiteSolicitudes');
    process.env.LIMITE_POST_POR_MIN = '3'; _reiniciar();
    const a = express(); a.set('trust proxy', 'loopback'); a.post('/x', limitarSolicitudes, (q, s) => s.json({ ok: true })); a.get('/x', (q, s) => s.json({ ok: true }));
    const s = http.createServer(a); await new Promise((r) => s.listen(0, '127.0.0.1', r));
    const u = `http://127.0.0.1:${s.address().port}/x`;
    try {
        const estados = []; for (let i = 0; i < 5; i++) estados.push((await fetch(u, { method: 'POST' })).status);
        assert.deepStrictEqual(estados, [200, 200, 200, 429, 429]);
        assert.strictEqual((await fetch(u)).status, 200);
    } finally { s.close(); process.env.LIMITE_POST_POR_MIN = '0'; }
});
