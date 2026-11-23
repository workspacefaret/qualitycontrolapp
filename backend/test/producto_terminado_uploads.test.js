// Producto Terminado: la subida de fotos usa la misma validación de contenido que control/Faret. Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const http = require('http');
const Module = require('module');

const calls = { hallazgos: [], registros: 0 };
class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        const t = text.replace(/\s+/g, ' ');
        if (/INSERT INTO registros_producto_terminado/.test(t)) { calls.registros++; return { recordset: [{ id: 77 }] }; }
        if (/INSERT INTO registro_pt_hallazgos/.test(t)) { calls.hallazgos.push({ ...this.p }); return { recordset: [{ id: 5 }] }; }
        const vis = /FROM parametros_control_visual WHERE id IN \(([\d,]+)\)/.exec(t);
        if (vis) return { recordset: vis[1].split(',').map(Number).filter((id) => !(defectosFaret.has(id) && this.p.empresa !== 'FARET')).map((id) => ({ id })) };
        return { recordset: [] };
    }
}
const defectosFaret = new Set([900]); // parametros_control_visual.empresa = 'FARET'
const sqlStub = new Proxy({}, {
    get: (_, k) => (k === 'Transaction' ? class { async begin() { } async commit() { } async rollback() { } } : k === 'Request' ? FakeRequest : () => 'T'),
});
const cargar = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    return cargar.call(this, request, ...rest);
};

const app = require('express')();
app.use('/api/producto-terminado', require('../src/routes/productoTerminado.routes'));
const dir = path.resolve(__dirname, '../uploads/producto_terminado');
const listar = () => (fs.existsSync(dir) ? fs.readdirSync(dir) : []);
const antes = new Set(listar());
let server; let base;
test.before(async () => { server = http.createServer(app); await new Promise((r) => server.listen(0, r)); base = `http://127.0.0.1:${server.address().port}/api/producto-terminado`; });
test.after(() => { server.close(); for (const f of listar()) if (!antes.has(f)) fs.unlinkSync(path.join(dir, f)); });

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100, 1)]);
const PAYLOAD = { usuarioId: 1, procesoPt: 'Pegado', empresa: 'X', cantidadLote: 100, turno: 'A', nivelInspeccion: 'II', aql: 1.5, letraCodigo: 'F', tamanoMuestra: 20, resultado: 'CONFORME', pallets: ['P1'], hallazgos: [{ origenId: 1, defectoIds: [1] }] };

const enviar = (archivos, payload = PAYLOAD) => {
    const fd = new FormData();
    fd.append('payload', JSON.stringify(payload));
    for (const [nombre, buf] of archivos) fd.append('fotos', new Blob([buf]), nombre);
    return fetch(`${base}/registros`, { method: 'POST', body: fd });
};
const reposo = () => new Promise((r) => setTimeout(r, 150)); // multer borra temporales de forma asíncrona
const nuevos = () => listar().filter((f) => !antes.has(f));

test('foto JPG real: se guarda con extensión derivada del contenido', async () => {
    const r = await enviar([['camara.png', JPEG]]);
    assert.strictEqual(r.status, 201);
    const h = calls.hallazgos.at(-1);
    assert.match(h.fotoNombreArchivo, /\.jpg$/);
    assert.match(h.fotoRuta, /^\/uploads\/producto_terminado\/.+\.jpg$/);
    assert.ok(fs.existsSync(path.join(dir, h.fotoNombreArchivo)));
});

test('HTML disfrazado de .jpg se rechaza (400) y no deja archivos', async () => {
    await reposo(); const antesN = nuevos().length;
    const r = await enviar([['x.jpg', Buffer.from('<script>alert(1)</script>')]]);
    assert.strictEqual(r.status, 400);
    await reposo();
    assert.strictEqual(nuevos().length, antesN);
});

test('SVG y .html se rechazan', async () => {
    for (const [n, c] of [['a.svg', '<svg onload=alert(1)/>'], ['a.html', '<html>']]) {
        assert.strictEqual((await enviar([[n, Buffer.from(c)]])).status, 400, n);
    }
});

test('foto de más de 25 MB responde 413', async () => {
    const grande = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(25 * 1024 * 1024 + 10, 1)]);
    assert.strictEqual((await enviar([['g.jpg', grande]])).status, 413);
});

test('hallazgos y fotos que no coinciden: 400 sin archivos huérfanos', async () => {
    await reposo(); const antesN = nuevos().length;
    const r = await enviar([['a.jpg', JPEG], ['b.jpg', JPEG]]);
    assert.strictEqual(r.status, 400);
    await reposo();
    assert.strictEqual(nuevos().length, antesN);
});

test('payload incompleto: 400 sin archivos huérfanos', async () => {
    await reposo(); const antesN = nuevos().length;
    const r = await enviar([['a.jpg', JPEG]], { hallazgos: [{}] });
    assert.strictEqual(r.status, 400);
    await reposo();
    assert.strictEqual(nuevos().length, antesN);
});

test('aislamiento por empresa: un defecto propio de FARET se rechaza en una inspección INNPACK y se acepta en FARET', async () => {
    const con = (empresa, defectoIds) => ({ ...PAYLOAD, empresa, hallazgos: [{ origenId: 1, observacion: 'x', defectoIds }] });
    const r1 = await enviar([['a.jpg', JPEG]], con('INNPACK', [900]));
    assert.strictEqual(r1.status, 400);
    assert.match((await r1.json()).message, /no corresponden a la empresa/);
    const r2 = await enviar([['a.jpg', JPEG]], con('FARET', [900, 10]));
    assert.strictEqual(r2.status, 201);
    const r3 = await enviar([['a.jpg', JPEG]], con('INNPACK', [10, 11]));
    assert.strictEqual(r3.status, 201);
    const r4 = await enviar([['a.jpg', JPEG]], con('INNPACK', ['x']));
    assert.strictEqual(r4.status, 400);
    await reposo();
});
