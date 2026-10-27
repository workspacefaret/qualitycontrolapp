// Pruebas del operador de máquina (QR INNPACK) y de la consistencia QR <-> migración 008.
// Sin base de datos real: se sustituye el pool por un doble que registra consultas y parámetros.
// Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const Module = require('module');

const calls = [];
const sqlStub = new Proxy({}, {
    get: (_, k) => {
        if (k === 'Transaction') return class { async begin() { calls.push('BEGIN'); } async commit() { calls.push('COMMIT'); } async rollback() { calls.push('ROLLBACK'); } };
        if (k === 'Request') return FakeRequest;
        return () => 'T';
    },
});

class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        calls.push({ text, p: this.p });
        if (/FROM maquinas m/.test(text)) return { recordset: [{ machineId: 6, processId: 3, processName: 'Troquelado', codigoQr: 'MAQ-TRO-104-1' }] };
        if (/FROM operadores_maquina\s+WHERE activo = 1\s+ORDER/.test(text)) return { recordset: [{ id: 1, proceso_id: 3, nombre: 'Kervin Mosquera' }, { id: 8, proceso_id: 4, nombre: 'Marcos Astorga' }] };
        if (/FROM operadores_maquina\s+WHERE activo = 1\s+AND proceso_id/.test(text)) return { recordset: [{ id: 1, proceso_id: this.p.processId, nombre: 'Kervin Mosquera' }] };
        // Operador 1 pertenece al proceso 3 (Troquelado)
        if (/FROM operadores_maquina\s+WHERE id/.test(text)) return { recordset: this.p.operadorMaquinaId === 1 && this.p.procesoId === 3 ? [{ id: 1 }] : [] };
        if (/INSERT INTO registros_control/.test(text)) return { recordset: [{ id: 99 }] };
        return { recordset: [] };
    }
}

const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) {
        return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    }
    return originalLoad.call(this, request, ...rest);
};
const control = require('../src/controllers/control.controller');
const catalogos = require('../src/controllers/catalogos.controller');

const mkRes = () => { const r = { code: 200 }; r.status = (c) => { r.code = c; return r; }; r.json = (b) => { r.body = b; return r; }; return r; };
const base = { usuarioId: 1, procesoId: 3, maquinaId: 6, turno: 'A', resultadoVisual: 'Cumple', fallasVisuales: [] };
const lastInsert = () => calls.filter((c) => c.text && /INSERT INTO registros_control/.test(c.text)).pop();
const quiet = () => { const w = console.warn, l = console.log; console.warn = console.log = () => {}; return () => { console.warn = w; console.log = l; }; };

test('contexto QR: operadores filtrados por el proceso de la máquina', async () => {
    const res = mkRes();
    await control.getContextoPorQr({ params: { codigoQr: 'MAQ-TRO-104-1' } }, res);
    assert.strictEqual(res.body.data[0].operadoresMaquina.length, 1);
    assert.strictEqual(res.body.data[0].operadoresMaquina[0].nombre, 'Kervin Mosquera');
});

test('catálogo offline: cada contexto trae solo los operadores de su proceso', async () => {
    const res = mkRes();
    await catalogos.getCatalogoOffline({}, res);
    const ctx = res.body.data.qrContexts[0];
    assert.deepStrictEqual(ctx.operadoresMaquina.map((o) => o.nombre), ['Kervin Mosquera']);
});

test('registro con operador válido: se guarda operador_maquina_id', async () => {
    const restore = quiet(); calls.length = 0; const res = mkRes();
    await control.crearRegistroControl({ body: { ...base, operadorMaquinaId: 1 } }, res); restore();
    assert.strictEqual(res.code, 201);
    assert.strictEqual(lastInsert().p.operadorMaquinaId, 1);
    assert.ok(/operador_maquina_id/.test(lastInsert().text));
    assert.ok(calls.includes('COMMIT'));
});

test('registro sin operador (APK antiguo): 201 y operador NULL', async () => {
    const restore = quiet(); calls.length = 0; const res = mkRes();
    await control.crearRegistroControl({ body: { ...base } }, res); restore();
    assert.strictEqual(res.code, 201);
    assert.strictEqual(lastInsert().p.operadorMaquinaId, null);
});

test('operador de otro proceso / inexistente: no rechaza la inspección, guarda NULL', async () => {
    const restore = quiet(); calls.length = 0; const res = mkRes();
    await control.crearRegistroControl({ body: { ...base, procesoId: 4, operadorMaquinaId: 1 } }, res); restore();
    assert.strictEqual(res.code, 201);
    assert.strictEqual(lastInsert().p.operadorMaquinaId, null);
});

test('registro offline sincronizado (payload multipart JSON) conserva el operador', async () => {
    const restore = quiet(); calls.length = 0; const res = mkRes();
    await control.crearRegistroControl({ body: { payload: JSON.stringify({ ...base, operadorMaquinaId: 1 }) } }, res); restore();
    assert.strictEqual(res.code, 201);
    assert.strictEqual(lastInsert().p.operadorMaquinaId, 1);
});

test('registro histórico/validaciones previas siguen vigentes: faltan datos obligatorios -> 400', async () => {
    const restore = quiet(); const res = mkRes();
    await control.crearRegistroControl({ body: { operadorMaquinaId: 1 } }, res); restore();
    assert.strictEqual(res.code, 400);
});

// --- Consistencia QR <-> migración 008 ---------------------------------------------------------
const root = path.resolve(__dirname, '..', '..');
const migracion = fs.readFileSync(path.join(root, 'backend/migrations/008_maquinas_operadores_troquelado_pegado.sql'), 'utf8');
const generador = fs.readFileSync(path.join(root, 'tools/generar_qr_maquinas.py'), 'utf8');
const codigosMigracion = [...migracion.matchAll(/N'(MAQ-[A-Z0-9-]+)'/g)].map((m) => m[1]);
const codigosGenerador = [...generador.matchAll(/'codigo_qr': '(MAQ-[A-Z0-9-]+)'/g)].map((m) => m[1]);

test('QR: 14 máquinas nuevas, sin duplicados, y cada código de la migración tiene su etiqueta', () => {
    assert.strictEqual(codigosMigracion.length, 14);
    assert.strictEqual(new Set(codigosMigracion).size, 14);
    for (const c of codigosMigracion) assert.ok(codigosGenerador.includes(c), `falta etiqueta QR para ${c}`);
    assert.strictEqual(new Set(codigosGenerador).size, codigosGenerador.length, 'códigos repetidos en el generador');
});

test('QR: los códigos nuevos respetan el prefijo de su proceso y caben en maquinas.codigo_qr (100)', () => {
    for (const c of codigosMigracion) {
        assert.ok(/^MAQ-(TRO|PEG)-/.test(c), c);
        assert.ok(c.length <= 100, c);
    }
    assert.strictEqual(codigosMigracion.filter((c) => c.startsWith('MAQ-TRO-')).length, 6);
    assert.strictEqual(codigosMigracion.filter((c) => c.startsWith('MAQ-PEG-')).length, 8);
});
