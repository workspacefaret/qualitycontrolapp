// Evidencias fotográficas y comentarios (QR INNPACK + Faret): subida real multipart contra los routers reales,
// con un doble de la base de datos. Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const Module = require('module');

// ---- doble de SQL Server --------------------------------------------------------------------
const db = { registros: new Map(), adjuntos: [], inserts: { control: 0, faret: 0 }, nextId: 1000 };
const sqlStub = new Proxy({}, {
    get: (_, k) => {
        if (k === 'Transaction') return class { async begin() { } async commit() { } async rollback() { } };
        if (k === 'Request') return FakeRequest;
        return () => 'T';
    },
});
class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        const t = text.replace(/\s+/g, ' ');
        if (/SELECT id FROM registros_control WHERE client_uuid/.test(t)) return { recordset: db.registros.has('c:' + this.p.clientUuid) ? [{ id: db.registros.get('c:' + this.p.clientUuid) }] : [] };
        if (/SELECT id FROM registros_calidad_faret WHERE client_uuid/.test(t)) return { recordset: db.registros.has('f:' + this.p.clientUuid) ? [{ id: db.registros.get('f:' + this.p.clientUuid) }] : [] };
        if (/INSERT INTO registros_control/.test(t)) { const id = ++db.nextId; db.inserts.control++; if (this.p.clientUuid) db.registros.set('c:' + this.p.clientUuid, id); return { recordset: [{ id }] }; }
        if (/INSERT INTO registros_calidad_faret\b/.test(t)) { const id = ++db.nextId; db.inserts.faret++; if (this.p.clientUuid) db.registros.set('f:' + this.p.clientUuid, id); return { recordset: [{ id }] }; }
        if (/INSERT INTO registro_adjuntos|INSERT INTO registro_calidad_faret_adjuntos/.test(t)) { db.adjuntos.push({ ...this.p }); return { recordset: [] }; }
        return { recordset: [] };
    }
}
const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    return originalLoad.call(this, request, ...rest);
};

const express = require('express');
const app = express();
app.use('/api/control', require('../src/routes/control.routes'));
app.use('/api/calidad-faret', require('../src/routes/calidadFaret.routes'));
const uploadsBase = path.resolve(__dirname, '../uploads');
const listar = (d) => (fs.existsSync(path.join(uploadsBase, d)) ? fs.readdirSync(path.join(uploadsBase, d)) : []);
const antes = { control: new Set(listar('control')), calidad_faret: new Set(listar('calidad_faret')) };
let server; let base;
test.before(async () => { server = http.createServer(app); await new Promise((r) => server.listen(0, r)); base = `http://127.0.0.1:${server.address().port}/api`; });
test.after(async () => {
    server.close();
    // limpia lo que crearon las pruebas
    for (const d of ['control', 'calidad_faret']) for (const f of listar(d)) if (!antes[d].has(f)) fs.unlinkSync(path.join(uploadsBase, d, f));
});

// ---- archivos de prueba ----------------------------------------------------------------------
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 1)]);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(200, 2)]);
const PDF = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.alloc(200, 3)]);
const HTML = Buffer.from('<html><script>alert(1)</script></html>');

const faretPayload = (extra = {}) => ({ nvFaret: 'NV1', nvVoBoAprobado: true, areaControl: '03-OFFSET', operador: 'ANDRES', maquina: 'M1', presentaDefectos: false, ...extra });
const controlPayload = (extra = {}) => ({ usuarioId: 1, procesoId: 3, maquinaId: 6, turno: 'A', resultadoVisual: 'Cumple', fallasVisuales: [], ...extra });
const enviar = async (ruta, campo, payload, archivos) => {
    const form = new FormData();
    form.append('payload', JSON.stringify(payload));
    for (const a of archivos) form.append(campo, new Blob([a.data], { type: 'application/octet-stream' }), a.nombre);
    const res = await fetch(`${base}${ruta}`, { method: 'POST', body: form });
    return { status: res.status, body: await res.json() };
};
const quiet = async (fn) => {
    const w = console.warn, l = console.log, e = console.error;
    console.warn = console.log = console.error = () => { };
    try { return await fn(); } finally { console.warn = w; console.log = l; console.error = e; }
};

test('Faret: inspección SIN defectos puede llevar fotos densitométricas (JPG + PNG) asociadas al registro correcto', async () => {
    db.adjuntos.length = 0;
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'dens1.jpg', data: JPEG }, { nombre: 'dens2.png', data: PNG }]));
    assert.strictEqual(r.status, 201);
    assert.strictEqual(db.adjuntos.length, 2);
    assert.ok(db.adjuntos.every((a) => a.registroId === r.body.data.registroId));
    assert.deepStrictEqual(db.adjuntos.map((a) => path.extname(a.nombreArchivo)), ['.jpg', '.png']);
    assert.ok(db.adjuntos.every((a) => a.rutaArchivo.startsWith('/uploads/calidad_faret/')));
    assert.ok(fs.existsSync(path.join(uploadsBase, 'calidad_faret', db.adjuntos[0].nombreArchivo)));
});

test('Faret: inspección sin fotos y con observaciones sigue guardando', async () => {
    db.adjuntos.length = 0;
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload({ observaciones: 'Densidad OK' }), []));
    assert.strictEqual(r.status, 201);
    assert.strictEqual(db.adjuntos.length, 0);
});

test('Faret: reintento con el mismo clientId NO duplica registro ni fotos', async () => {
    db.inserts.faret = 0; db.adjuntos.length = 0;
    const payload = faretPayload({ clientId: 'faret-retry-0001' });
    const a = await quiet(() => enviar('/calidad-faret/registros', 'archivos', payload, [{ nombre: 'f.jpg', data: JPEG }]));
    const filesTrasPrimero = listar('calidad_faret').length;
    const b = await quiet(() => enviar('/calidad-faret/registros', 'archivos', payload, [{ nombre: 'f.jpg', data: JPEG }]));
    assert.strictEqual(a.status, 201);
    assert.strictEqual(b.status, 200);
    assert.strictEqual(b.body.duplicado, true);
    assert.strictEqual(b.body.data.registroId, a.body.data.registroId);
    assert.strictEqual(db.inserts.faret, 1);
    assert.strictEqual(db.adjuntos.length, 1);
    assert.strictEqual(listar('calidad_faret').length, filesTrasPrimero, 'el archivo del reintento no debe quedar en disco');
});

test('archivo falso (HTML renombrado .jpg) se rechaza y no queda nada en disco', async () => {
    const antesN = listar('calidad_faret').length;
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'x.jpg', data: HTML }]));
    assert.strictEqual(r.status, 400);
    assert.match(r.body.message, /JPG\/PNG ni un PDF válido/);
    assert.strictEqual(listar('calidad_faret').length, antesN);
});

test('archivo .html con contenido HTML se rechaza (no se sirve como página desde /uploads)', async () => {
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'x.html', data: HTML }]));
    assert.strictEqual(r.status, 400);
});

test('foto sin extensión en el nombre (cámara web) se acepta y se guarda con la extensión real', async () => {
    db.adjuntos.length = 0;
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'blob', data: JPEG }]));
    assert.strictEqual(r.status, 201);
    assert.strictEqual(path.extname(db.adjuntos[0].nombreArchivo), '.jpg');
});

test('PDF válido se acepta', async () => {
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'informe.pdf', data: PDF }]));
    assert.strictEqual(r.status, 201);
});

test('archivo mayor a 25 MB -> 413 con mensaje claro y sin residuos', async () => {
    const antesN = listar('calidad_faret').length;
    const grande = Buffer.concat([JPEG, Buffer.alloc(26 * 1024 * 1024, 7)]);
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), [{ nombre: 'grande.jpg', data: grande }]));
    assert.strictEqual(r.status, 413);
    assert.match(r.body.message, /25 MB/);
    assert.strictEqual(listar('calidad_faret').length, antesN);
});

test('más de 5 archivos -> 400', async () => {
    const seis = Array.from({ length: 6 }, (_, i) => ({ nombre: `f${i}.jpg`, data: JPEG }));
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', faretPayload(), seis));
    assert.strictEqual(r.status, 400);
});

test('datos obligatorios faltantes (400) no dejan archivos huérfanos', async () => {
    const antesN = listar('calidad_faret').length;
    const r = await quiet(() => enviar('/calidad-faret/registros', 'archivos', { nvFaret: '' }, [{ nombre: 'f.jpg', data: JPEG }]));
    assert.strictEqual(r.status, 400);
    assert.strictEqual(listar('calidad_faret').length, antesN);
});

test('INNPACK QR: control Conforme con foto, asociada al registro correcto', async () => {
    db.adjuntos.length = 0;
    const r = await quiet(() => enviar('/control/registros', 'archivo', controlPayload({ observacion: 'Densidad dentro de rango' }), [{ nombre: 'foto.jpg', data: JPEG }]));
    assert.strictEqual(r.status, 201);
    assert.strictEqual(db.adjuntos.length, 1);
    assert.strictEqual(db.adjuntos[0].registroId, r.body.data.registroId);
    assert.ok(db.adjuntos[0].rutaArchivo.startsWith('/uploads/control/'));
});

test('INNPACK QR: control sin foto (APK anterior, sin clientId) sigue funcionando', async () => {
    const r = await quiet(() => enviar('/control/registros', 'archivo', controlPayload(), []));
    assert.strictEqual(r.status, 201);
});

test('INNPACK QR: reintento (p. ej. sincronización offline repetida) con el mismo clientId no duplica', async () => {
    db.inserts.control = 0; db.adjuntos.length = 0;
    const payload = controlPayload({ clientId: 'ctl-retry-000001', operadorMaquinaId: 1 });
    const a = await quiet(() => enviar('/control/registros', 'archivo', payload, [{ nombre: 'foto.png', data: PNG }]));
    const b = await quiet(() => enviar('/control/registros', 'archivo', payload, [{ nombre: 'foto.png', data: PNG }]));
    assert.strictEqual(a.status, 201);
    assert.strictEqual(b.status, 200);
    assert.strictEqual(b.body.duplicado, true);
    assert.strictEqual(b.body.data.registroId, a.body.data.registroId);
    assert.strictEqual(db.inserts.control, 1);
    assert.strictEqual(db.adjuntos.length, 1);
});

test('INNPACK QR: archivo falso rechazado con 400', async () => {
    const r = await quiet(() => enviar('/control/registros', 'archivo', controlPayload(), [{ nombre: 'x.png', data: HTML }]));
    assert.strictEqual(r.status, 400);
});

// ---- limpieza de huérfanos -------------------------------------------------------------------
test('limpieza: detecta temporales .upload y archivos sin registro, respeta los referenciados y los recientes', () => {
    const { listarHuerfanos } = require('../scripts/limpiar_adjuntos_huerfanos');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'huerfanos-'));
    const viejo = Date.now() - 48 * 3600 * 1000;
    const crear = (n, edad) => { const f = path.join(dir, n); fs.writeFileSync(f, 'x'); fs.utimesSync(f, new Date(edad), new Date(edad)); };
    crear('1-1.upload', viejo); crear('2-2.jpg', viejo); crear('3-3.jpg', viejo); crear('4-4.jpg', Date.now());
    const h = listarHuerfanos({ dir, referenciados: new Set(['3-3.jpg']) });
    assert.deepStrictEqual(h.map((x) => path.basename(x.ruta)).sort(), ['1-1.upload', '2-2.jpg']);
    assert.deepStrictEqual(listarHuerfanos({ dir, referenciados: null }).map((x) => path.basename(x.ruta)), ['1-1.upload']);
    fs.rmSync(dir, { recursive: true, force: true });
});
