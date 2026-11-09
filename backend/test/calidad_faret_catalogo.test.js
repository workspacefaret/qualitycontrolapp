// Catálogo de eventos de Calidad FARET (migración 010) en el backend. Sin base real: doble de SQL cuyo catálogo se lee del
// SEED de la propia migración (57 eventos / 8 áreas), de modo que las pruebas usan los datos oficiales y no copias a mano.
// Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const Module = require('module');

// ---- Catálogo oficial leído del SQL de la migración ----
const sqlMigracion = fs.readFileSync(path.join(__dirname, '../migrations/010_catalogo_eventos_calidad_faret.sql'), 'utf8');
const AREAS = [...sqlMigracion.matchAll(/^\s*\(N'([A-Z]{3})', N'([^']+)', N'([^']+)', (\d+), N'Activo'\)/gm)]
    .map((m) => ({ cod_area: m[1], nombre: m[2], area_control: m[3], orden: Number(m[4]) }));
const EVENTOS = [...sqlMigracion.matchAll(/^\s*\(N'([A-Z]{3}-\d{3})', N'([A-Z]{3})', N'[^']*', N'((?:[^']|'')*)', N'(Critico|Mayor|Menor)', N'Activo', (NULL|N'[^']*'), N'(?:[^']|'')*', (\d+)\)/gm)]
    .map((m) => ({ id_evento: m[1], cod_area: m[2], defecto: m[3].replace(/''/g, "'"), criticidad: m[4], pendiente: m[5] !== 'NULL', orden_evento: Number(m[6]) }));
const PENDIENTES = ['SER-007', 'FOL-007', 'PEG-007', 'PEG-008', 'CYD-003'];
const operables = () => EVENTOS.filter((e) => !e.pendiente);
const areaDe = (cod) => AREAS.find((a) => a.cod_area === cod);

// ---- Doble de SQL ----
let calls = [];
let fallo = null;               // { re, error } fuerza un error SQL en la consulta que coincida
let existeCatalogo = true;
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
        calls.push({ text, p: { ...this.p } });
        if (fallo && fallo.re.test(text)) throw fallo.error;
        if (/FROM dbo\.calidad_faret_areas/.test(text)) {
            if (!existeCatalogo) throw Object.assign(new Error('Invalid object name'), { number: 208 });
            return { recordset: AREAS };
        }
        if (/FROM dbo\.vw_calidad_faret_eventos_operables\s+ORDER/.test(text)) {
            return { recordset: operables().map((e) => ({ ...e, area_control: areaDe(e.cod_area).area_control })) };
        }
        if (/FROM dbo\.vw_calidad_faret_eventos_operables WHERE id_evento IN/.test(text)) {
            if (!existeCatalogo) throw Object.assign(new Error('Invalid object name'), { number: 208 });
            const ids = Object.values(this.p);
            return { recordset: operables().filter((e) => ids.includes(e.id_evento)).map((e) => ({ id_evento: e.id_evento, area_control: areaDe(e.cod_area).area_control, defecto: e.defecto, criticidad: e.criticidad })) };
        }
        if (/SELECT id FROM registros_calidad_faret WHERE client_uuid/.test(text)) return { recordset: [] };
        if (/INSERT INTO registros_calidad_faret/.test(text)) return { recordset: [{ id: 501 }] };
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
const ctl = require('../src/controllers/calidadFaret.controller');
const util = require('../src/utils/eventosCalidadFaret');

const mkRes = () => {
    const r = { code: 200, headers: {} };
    r.status = (c) => { r.code = c; return r; };
    r.json = (b) => { r.body = b; return r; };
    r.set = (k, v) => { r.headers[k] = v; return r; };
    r.end = () => r;
    return r;
};
const silencio = () => { const w = console.warn, e = console.error; const out = { warn: [], error: [] }; console.warn = (m) => out.warn.push(String(m)); console.error = (m) => out.error.push(String(m)); return { out, restaurar: () => { console.warn = w; console.error = e; } }; };
const registro = (extra = {}) => ({
    nvFaret: 'NV-1', areaControl: '03-OFFSET', operador: 'X', maquina: 'KBA 2', presentaDefectos: true, areaDefecto: '03-OFFSET', defectos: [], ...extra,
});
const enviar = async (cuerpo) => {
    calls = [];
    const res = mkRes();
    await ctl.crearRegistroCalidadFaret({ body: { payload: JSON.stringify(cuerpo) }, files: [], headers: {} }, res);
    return res;
};
const insertsDefecto = () => calls.filter((c) => c.text && /INSERT INTO registro_calidad_faret_defectos/.test(c.text));
const reiniciar = () => { calls = []; fallo = null; existeCatalogo = true; util._vaciarCache(); util._reiniciarAvisos(); delete process.env.CALIDAD_FARET_EVENTOS_LEGACY; };

// ---------------------------------------------------------------------------------------------------------------------
test('el doble lee el catálogo oficial: 8 áreas, 57 eventos, 42/14/1 y 5 pendientes', () => {
    assert.strictEqual(AREAS.length, 8);
    assert.strictEqual(EVENTOS.length, 57);
    const cuenta = (c) => EVENTOS.filter((e) => e.criticidad === c).length;
    assert.deepStrictEqual([cuenta('Critico'), cuenta('Mayor'), cuenta('Menor')], [42, 14, 1]);
    assert.deepStrictEqual(EVENTOS.filter((e) => e.pendiente).map((e) => e.id_evento).sort(), [...PENDIENTES].sort());
});

test('GET catálogo: 8 áreas, 52 eventos operables, sin los 5 pendientes, con ETag y 304', async () => {
    reiniciar();
    const r1 = mkRes();
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: {} }, r1);
    assert.strictEqual(r1.code, 200);
    const d = r1.body.data;
    assert.strictEqual(d.areas.length, 8);
    assert.strictEqual(d.totales.eventos, 52);
    const ids = d.areas.flatMap((a) => a.eventos.map((e) => e.idEvento));
    assert.strictEqual(ids.length, 52);
    for (const p of PENDIENTES) assert.ok(!ids.includes(p), `${p} no debe aparecer`);
    assert.deepStrictEqual(Object.keys(d.areas[0]).sort(), ['areaControl', 'codArea', 'eventos', 'nombre', 'orden']);
    assert.deepStrictEqual(Object.keys(d.areas[0].eventos[0]).sort(), ['criticidad', 'defecto', 'idEvento', 'orden']);
    const crit = d.areas.flatMap((a) => a.eventos).reduce((m, e) => ({ ...m, [e.criticidad]: (m[e.criticidad] || 0) + 1 }), {});
    assert.deepStrictEqual(crit, { Critico: 38, Mayor: 13, Menor: 1 });   // 42/14/1 menos los pendientes (4 críticos y 1 mayor)
    assert.strictEqual(r1.headers['Cache-Control'], 'no-cache');
    const etag = r1.headers.ETag;
    assert.match(etag, /^"[0-9a-f]{16}"$/);
    const r2 = mkRes();
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: { 'if-none-match': etag } }, r2);
    assert.strictEqual(r2.code, 304);
    assert.strictEqual(r2.body, undefined);
    assert.ok(!JSON.stringify(r1.body).match(/estado|aprob|row_version|created|updated/i), 'no expone campos internos');
});

test('GET catálogo: filtrado por área = eventos agrupados solo en su área', async () => {
    reiniciar();
    const r = mkRes();
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: {} }, r);
    for (const a of r.body.data.areas) {
        const esperados = operables().filter((e) => e.cod_area === a.codArea).map((e) => e.id_evento);
        assert.deepStrictEqual(a.eventos.map((e) => e.idEvento), esperados);
        assert.ok(a.eventos.every((e) => e.idEvento.startsWith(a.codArea)));
    }
});

test('GET catálogo: error SQL o catálogo ausente = 503 sin filtrar detalles internos', async () => {
    reiniciar();
    existeCatalogo = false;
    const s = silencio();
    const r = mkRes();
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: {} }, r);
    s.restaurar();
    assert.strictEqual(r.code, 503);
    assert.deepStrictEqual(Object.keys(r.body).sort(), ['message', 'ok']);
    assert.ok(!/Invalid object/.test(JSON.stringify(r.body)));
});

test('GET catálogo: la caché evita consultas repetidas (30 s) pero el POST siempre consulta SQL', async () => {
    reiniciar();
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: {} }, mkRes());
    const n = calls.length;
    await ctl.obtenerCatalogoEventosCalidadFaret({ headers: {} }, mkRes());
    assert.strictEqual(calls.length, n, 'segunda lectura desde caché');
    calls = [];
    await enviar(registro({ defectos: [{ idEvento: 'OFF-001' }] }));
    assert.ok(calls.some((c) => c.text && /IN \(@e0\)/.test(c.text)), 'el POST valida contra SQL, no contra la caché');
});

// ---------------------------------------------------------------------------------------------------------------------
test('POST con {idEvento}: guarda texto y criticidad del catálogo e ignora lo que mande el cliente', async () => {
    reiniciar();
    const ev = operables().find((e) => e.cod_area === 'OFF');
    const res = await enviar(registro({ defectos: [{ idEvento: ev.id_evento, criticidad: 'Menor', defecto: 'texto falso', area: 'otra' }] }));
    assert.strictEqual(res.code, 201);
    const ins = insertsDefecto();
    assert.strictEqual(ins.length, 1);
    assert.deepStrictEqual({ d: ins[0].p.defecto, i: ins[0].p.idEvento, c: ins[0].p.criticidad }, { d: ev.defecto, i: ev.id_evento, c: ev.criticidad });
    assert.deepStrictEqual(calls.filter((c) => typeof c === 'string'), ['BEGIN', 'COMMIT']);
});

test('POST: acepta TODOS los eventos operables en su área (52) y registra su criticidad oficial', async () => {
    reiniciar();
    for (const cod of [...new Set(operables().map((e) => e.cod_area))]) {
        const evs = operables().filter((e) => e.cod_area === cod);
        const res = await enviar(registro({ areaControl: areaDe(cod).area_control, areaDefecto: areaDe(cod).area_control, defectos: evs.map((e) => ({ idEvento: e.id_evento })) }));
        assert.strictEqual(res.code, 201, cod);
        const ins = insertsDefecto();
        assert.strictEqual(ins.length, evs.length);
        ins.forEach((i, k) => assert.strictEqual(i.p.criticidad, evs[k].criticidad));
    }
});

test('POST: los 5 eventos pendientes de Calidad se rechazan con 400 y nada se escribe', async () => {
    reiniciar();
    for (const id of PENDIENTES) {
        const ev = EVENTOS.find((e) => e.id_evento === id);
        const area = areaDe(ev.cod_area).area_control;
        const res = await enviar(registro({ areaControl: area, areaDefecto: area, defectos: [{ idEvento: id }] }));
        assert.strictEqual(res.code, 400, id);
        assert.ok(!calls.includes('BEGIN'), 'no abre transacción');
        assert.strictEqual(calls.filter((c) => c.text && /INSERT/.test(c.text)).length, 0);
    }
});

test('POST: evento inexistente, formato inválido, área incorrecta o sin área = 400', async () => {
    reiniciar();
    const off = operables().find((e) => e.cod_area === 'OFF').id_evento;
    const casos = [
        [{ idEvento: 'OFF-999' }],                         // no existe
        [{ idEvento: 'xx' }], [{ idEvento: 123 }], [{}],   // formato
        [{ idEvento: "OFF-001'; DROP TABLE x;--" }],       // inyección: nunca llega a SQL
        [['OFF-001']], [null], [42],                        // tipos no admitidos
        [{ idEvento: off }, { idEvento: 'TRO-001' }],      // uno de otra área
    ];
    for (const defectos of casos) {
        const res = await enviar(registro({ defectos }));
        assert.strictEqual(res.code, 400, JSON.stringify(defectos));
        assert.ok(!calls.includes('BEGIN'));
    }
    const sinArea = await enviar(registro({ areaDefecto: null, defectos: [{ idEvento: off }] }));
    assert.strictEqual(sinArea.code, 400);
    const noLista = await enviar(registro({ defectos: 'OFF-001' }));
    assert.strictEqual(noLista.code, 400);
    const muchos = await enviar(registro({ defectos: Array.from({ length: 101 }, () => 'x') }));
    assert.strictEqual(muchos.code, 400);
});

test('POST: eventos repetidos se guardan una sola vez; sin presentaDefectos no se guarda ninguno', async () => {
    reiniciar();
    const off = operables().find((e) => e.cod_area === 'OFF').id_evento;
    const r = await enviar(registro({ defectos: [{ idEvento: off }, { idEvento: off.toLowerCase() }] }));
    assert.strictEqual(r.code, 201);
    assert.strictEqual(insertsDefecto().length, 1);
    const r2 = await enviar(registro({ presentaDefectos: false, defectos: [{ idEvento: 'ZZZ-000' }, 'texto'] }));
    assert.strictEqual(r2.code, 201);
    assert.strictEqual(insertsDefecto().length, 0);
});

// ---------------------------------------------------------------------------------------------------------------------
test('cliente antiguo (strings): mismo INSERT de siempre, sin id_evento ni criticidad, y no consulta el catálogo', async () => {
    reiniciar();
    const s = silencio();
    const res = await enviar(registro({ defectos: ['DIFERENCIA DE TONO', 'ARRUGAS'] }));
    s.restaurar();
    assert.strictEqual(res.code, 201);
    const ins = insertsDefecto();
    assert.strictEqual(ins.length, 2);
    for (const i of ins) {
        assert.ok(!/id_evento|criticidad/.test(i.text), 'INSERT legado no menciona columnas de la 010');
        assert.strictEqual(i.p.idEvento, undefined);
    }
    assert.ok(!calls.some((c) => c.text && /vw_calidad_faret_eventos_operables/.test(c.text)));
});

test('modo legado: observar (defecto) avisa agrupado y sin contenido; off no avisa; exigir rechaza con 400', async () => {
    reiniciar();
    let s = silencio();
    await enviar(registro({ defectos: ['DATO CONFIDENCIAL X'] }));
    await enviar(registro({ defectos: ['OTRO'] }));
    await enviar(registro({ defectos: ['OTRO'] }));
    s.restaurar();
    assert.strictEqual(s.out.warn.length, 1, 'un solo aviso agrupado');
    assert.ok(!/CONFIDENCIAL|OTRO|NV-1/.test(s.out.warn[0]), 'sin datos de la inspección');

    reiniciar(); process.env.CALIDAD_FARET_EVENTOS_LEGACY = 'off';
    s = silencio(); const r1 = await enviar(registro({ defectos: ['A'] })); s.restaurar();
    assert.strictEqual(r1.code, 201); assert.strictEqual(s.out.warn.length, 0);

    reiniciar(); process.env.CALIDAD_FARET_EVENTOS_LEGACY = 'exigir';
    const r2 = await enviar(registro({ defectos: ['A'] }));
    assert.strictEqual(r2.code, 400);
    const ok = await enviar(registro({ defectos: [{ idEvento: operables()[0].id_evento }], areaControl: areaDe(operables()[0].cod_area).area_control, areaDefecto: areaDe(operables()[0].cod_area).area_control }));
    assert.strictEqual(ok.code, 201, 'en exigir los eventos del catálogo sí pasan');

    reiniciar(); process.env.CALIDAD_FARET_EVENTOS_LEGACY = 'valor-raro';
    assert.strictEqual(util.modoLegado(), 'observar', 'valor inválido = observar (compatible)');
    reiniciar();
});

test('mezcla strings + objetos en una misma inspección (transición)', async () => {
    reiniciar();
    const s = silencio();
    const ev = operables().find((e) => e.cod_area === 'OFF');
    const res = await enviar(registro({ defectos: ['TEXTO VIEJO', { idEvento: ev.id_evento }] }));
    s.restaurar();
    assert.strictEqual(res.code, 201);
    const ins = insertsDefecto();
    assert.strictEqual(ins.length, 2);
    assert.strictEqual(ins[0].p.idEvento, undefined);
    assert.strictEqual(ins[1].p.idEvento, ev.id_evento);
});

// ---------------------------------------------------------------------------------------------------------------------
test('transacciones: carrera con el trigger (51030/51031) = 400 y ROLLBACK; otro error SQL = 500 y ROLLBACK', async () => {
    reiniciar();
    const ev = operables().find((e) => e.cod_area === 'OFF');
    for (const numero of [51030, 51031, 51032]) {
        fallo = { re: /INSERT INTO registro_calidad_faret_defectos\s+\(registro_id, defecto, id_evento/, error: Object.assign(new Error('trigger'), { number: numero }) };
        const res = await enviar(registro({ defectos: [{ idEvento: ev.id_evento }] }));
        assert.strictEqual(res.code, 400, String(numero));
        assert.deepStrictEqual(calls.filter((c) => typeof c === 'string'), ['BEGIN', 'ROLLBACK']);
        assert.ok(!/trigger/.test(JSON.stringify(res.body)));
    }
    fallo = { re: /INSERT INTO registro_calidad_faret_defectos/, error: Object.assign(new Error('deadlock'), { number: 1205 }) };
    const s = silencio();
    const res = await enviar(registro({ defectos: ['A'] }));
    s.restaurar();
    assert.strictEqual(res.code, 500);
    assert.deepStrictEqual(calls.filter((c) => typeof c === 'string'), ['BEGIN', 'ROLLBACK']);
});

test('010 no aplicada: {idEvento} = 503 sin escribir; clientes con strings siguen funcionando', async () => {
    reiniciar();
    existeCatalogo = false;
    const r1 = await enviar(registro({ defectos: [{ idEvento: 'OFF-001' }] }));
    assert.strictEqual(r1.code, 503);
    assert.ok(!calls.includes('BEGIN'));
    const s = silencio();
    const r2 = await enviar(registro({ defectos: ['ARRUGAS'] }));
    s.restaurar();
    assert.strictEqual(r2.code, 201);
});

test('regresión: campos obligatorios y reintento con clientId (duplicado) siguen igual', async () => {
    reiniciar();
    const faltan = await enviar({ nvFaret: '' });
    assert.strictEqual(faltan.code, 400);
    const ok = await enviar(registro({ presentaDefectos: false, defectos: undefined }));
    assert.strictEqual(ok.code, 201);
    assert.deepStrictEqual(ok.body.data, { registroId: 501 });
});

test('seguridad: la ruta del catálogo es pública y de solo lectura; el resto conserva su autorización', () => {
    const src = fs.readFileSync(path.join(__dirname, '../src/routes/calidadFaret.routes.js'), 'utf8');
    assert.match(src, /router\.get\('\/catalogo-eventos', obtenerCatalogoEventosCalidadFaret\)/);
    assert.ok(!/router\.(post|put|delete|patch)\('\/catalogo-eventos/.test(src), 'sin escritura sobre el catálogo');
    for (const r of ["get('/registros'", "get('/resumen'", "get('/maquinas/resumen'", "get('/registros/:id/adjuntos'"]) {
        assert.match(src, new RegExp(`router\\.${r.replace(/[()/:]/g, '\\$&')}[^\\n]*autorizar\\('leer'`));
    }
    assert.match(src, /router\.delete\('\/registros\/:id', autorizar\('borrar'/);
});

test('el backend solo lee el catálogo (jamás INSERT/UPDATE/DELETE sobre las tablas de la 010)', () => {
    const src = fs.readFileSync(path.join(__dirname, '../src/utils/eventosCalidadFaret.js'), 'utf8') + fs.readFileSync(path.join(__dirname, '../src/controllers/calidadFaret.controller.js'), 'utf8');
    assert.ok(!/(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+(dbo\.)?calidad_faret_(areas|eventos|catalogo_auditoria)/i.test(src));
    assert.ok(!/calidad_faret_catalogo_auditoria/.test(src), 'la app no tiene permiso sobre la auditoría y no la consulta');
});
