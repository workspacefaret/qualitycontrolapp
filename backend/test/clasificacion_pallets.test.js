// Pruebas de la clasificación de pallets INNPACK (AZUL/ROJO/VERDE). Sin bases reales: dobles de calidad_db y de FPS.
// Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const Module = require('module');

const calls = [];
const state = {
    fps: { ok: true },            // false => FPS lanza error (caída)
    tarjas: {},                   // codigo -> fila de FPS
    etiquetasDeRegistro: {},      // recordKey -> [{codigo, n_etiqueta, cantidad}]
    existeSinRegistro: new Set(), // etiquetas que existen pero sin WorkOrderRecords
    uuidExistente: null,
    vigente: null,
    defectosValidos: [1, 2, 3],
    fallaInsertPallet: false,
    nextId: 500,
};

const fakeTransaction = class {
    async begin() { calls.push('BEGIN'); }
    async commit() { calls.push('COMMIT'); }
    async rollback() { calls.push('ROLLBACK'); }
};

class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        calls.push({ text, p: { ...this.p } });
        if (/SAVE TRANSACTION|ROLLBACK TRANSACTION/.test(text)) return { recordset: [] };
        if (/SELECT id FROM registros_control WHERE client_uuid/.test(text)) return { recordset: state.uuidExistente ? [{ id: state.uuidExistente }] : [] };
        if (/INSERT INTO registros_control/.test(text)) return { recordset: [{ id: 99 }] };
        if (/INSERT INTO pallet_clasificaciones/.test(text)) {
            if (state.fallaInsertPallet) throw new Error("Invalid object name 'pallet_clasificaciones'.");
            return { recordset: [{ id: state.nextId++ }] };
        }
        if (/FROM parametros_control_visual\s+WHERE proceso_id/.test(text)) {
            const pedidos = Object.entries(this.p).filter(([k]) => /^d\d+$/.test(k)).map(([, v]) => v);
            return { recordset: pedidos.filter((id) => state.defectosValidos.includes(id)).map((id) => ({ id })) };
        }
        if (/FROM pallet_clasificaciones\s+WHERE pallet_codigo = @codigo AND anulado = 0/.test(text)) {
            return { recordset: state.vigente ? [state.vigente] : [] };
        }
        // ---- FPS ----
        if (/FROM ETIQUETAS_PRODUCCIONES E\s+INNER JOIN WorkOrderRecords/.test(text)) {
            if (!state.fps.ok) throw new Error('FPS caído');
            const f = state.tarjas[this.p.codigo];
            return { recordset: f ? [f] : [] };
        }
        if (/SELECT TOP 1 1 AS x FROM ETIQUETAS_PRODUCCIONES/.test(text)) return { recordset: state.existeSinRegistro.has(this.p.codigo) ? [{ x: 1 }] : [] };
        if (/WHERE CodigoPadre = @recordKey/.test(text)) {
            if (!state.fps.ok) throw new Error('FPS caído');
            return { recordset: state.etiquetasDeRegistro[this.p.recordKey] || [] };
        }
        return { recordset: [] };
    }
}

const sqlStub = new Proxy({}, {
    get: (_, k) => {
        if (k === 'Transaction') return fakeTransaction;
        if (k === 'Request') return FakeRequest;
        return () => 'T';
    },
});

const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    if (request.endsWith('sqlServerPool')) return { sql: sqlStub, getSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    return originalLoad.call(this, request, ...rest);
};

const util = require('../src/utils/clasificacionPallets');
const pallets = require('../src/controllers/clasificacionPallets.controller');
const control = require('../src/controllers/control.controller');

const mkRes = () => { const r = { code: 200 }; r.status = (c) => { r.code = c; return r; }; r.json = (b) => { r.body = b; return r; }; return r; };
const quiet = () => { const w = console.warn, l = console.log, e = console.error; console.warn = console.log = console.error = () => {}; return () => { console.warn = w; console.log = l; console.error = e; }; };
const reset = () => { calls.length = 0; state.fps.ok = true; state.uuidExistente = null; state.vigente = null; state.fallaInsertPallet = false; state.defectosValidos = [1, 2, 3]; };

const FILA = (codigo, extra = {}) => ({
    codigo, record_key: codigo.split('-')[0], n_etiqueta: Number(codigo.split('-')[1]), cantidad: 0, total_etiquetas: 25, registro_activo: true,
    fecha_tarja: new Date('2026-11-22T21:08:49.730Z'), orden_fabricacion: 22669, np_faret: 22669, np_innpack: 3957, cliente: 'INNPACK SpA-A.G. SERVICIOS SPA',
    item_np: '1', codigo_producto: 'ST1102266931170', producto: 'PLIEGO TROQUELADO ', proceso: 'TROQUEL', maquina: 'BOBST 142 - 2 (SFM)', operador: 'LUIS MONTOYA', ...extra,
});
state.tarjas['466568-1'] = FILA('466568-1');
state.tarjas['466568-2'] = FILA('466568-2', { cantidad: 1200 });
state.tarjas['466568-3'] = FILA('466568-3');

const base = { usuarioId: 1, procesoId: 3, maquinaId: 6, turno: 'A', resultadoVisual: 'Cumple', fallasVisuales: [] };
const palletCalls = () => calls.filter((c) => c.text && /pallet_clasificaci/.test(c.text));
const inserts = () => calls.filter((c) => c.text && /INSERT INTO pallet_clasificaciones/.test(c.text));
const guardar = async (body, extra = {}) => { const res = mkRes(); const restore = quiet(); await control.crearRegistroControl({ body, ...extra }, res); restore(); return res; };

// ---------------- Interpretación del código del QR ----------------
test('interpretarCodigo: pallet, registro solo y entradas inválidas / maliciosas', () => {
    assert.deepStrictEqual(util.interpretarCodigo('466568-1'), { tipo: 'pallet', codigo: '466568-1', recordKey: '466568', nEtiqueta: 1 });
    assert.deepStrictEqual(util.interpretarCodigo('  466568-12\r\n'), { tipo: 'pallet', codigo: '466568-12', recordKey: '466568', nEtiqueta: 12 });
    assert.deepStrictEqual(util.interpretarCodigo('134315-09'), { tipo: 'pallet', codigo: '134315-09', recordKey: '134315', nEtiqueta: 9 });
    assert.deepStrictEqual(util.interpretarCodigo('466568'), { tipo: 'registro', recordKey: '466568' });
    for (const malo of ["1' OR '1'='1", '466568-', '-1', 'FPS-OF-22669', '12-34-56', '', null, undefined, 123456, '466568-1; DROP TABLE x', '1234567890123']) {
        assert.strictEqual(util.interpretarCodigo(malo), null, `debe rechazar ${JSON.stringify(malo)}`);
    }
});

test('fechas: hora de pared de FPS sin desfase de zona', () => {
    assert.strictEqual(util.aHoraPared(new Date('2026-11-22T21:08:49.730Z')), '2026-11-22T21:08:49');
    assert.strictEqual(util.desdeHoraPared('2026-11-22T21:08:49').toISOString(), '2026-11-22T21:08:49.000Z');
    assert.strictEqual(util.desdeHoraPared('basura'), null);
});

// ---------------- Consulta de tarja ----------------
test('tarja: recupera los datos de FPS; cantidad 0 = sin cantidad; consulta parametrizada', async () => {
    reset();
    const res = mkRes();
    await pallets.obtenerTarja({ params: { codigo: '466568-1' } }, res);
    assert.strictEqual(res.code, 200);
    const d = res.body.data;
    assert.strictEqual(d.codigo, '466568-1');
    assert.strictEqual(d.ordenFabricacion, '22669');
    assert.strictEqual(d.npInnpack, '3957');
    assert.strictEqual(d.cliente, 'INNPACK SpA-A.G. SERVICIOS SPA');
    assert.strictEqual(d.producto, 'PLIEGO TROQUELADO');
    assert.strictEqual(d.maquina, 'BOBST 142 - 2 (SFM)');
    assert.strictEqual(d.operador, 'LUIS MONTOYA');
    assert.strictEqual(d.cantidad, null);
    assert.strictEqual(d.totalEtiquetas, 25);
    assert.strictEqual(d.fechaTarja, '2026-11-22T21:08:49');
    assert.strictEqual(d.estadoActual, null);
    const q = calls.find((c) => c.text && /INNER JOIN WorkOrderRecords/.test(c.text));
    assert.strictEqual(q.p.codigo, '466568-1');
    assert.ok(!q.text.includes('466568'), 'el código nunca va dentro del texto SQL');
});

test('tarja: con cantidad y con clasificación vigente previa (para reclasificar)', async () => {
    reset();
    state.vigente = { id: 7, color: 'AZUL', clasificado_en: new Date('2026-11-23T10:30:00.000Z') };
    const res = mkRes();
    await pallets.obtenerTarja({ params: { codigo: '466568-2' } }, res);
    assert.strictEqual(res.body.data.cantidad, 1200);
    assert.deepStrictEqual(res.body.data.estadoActual, { id: 7, color: 'AZUL', clasificadoEn: '2026-11-23T10:30:00' });
});

test('tarja: errores claros (inválida, inexistente, sin registro de producción, FPS caído)', async () => {
    reset();
    state.existeSinRegistro.add('900000-1');
    let r = mkRes(); await pallets.obtenerTarja({ params: { codigo: "1' OR '1'='1" } }, r);
    assert.strictEqual(r.code, 400); assert.strictEqual(r.body.code, 'CODIGO_INVALIDO');
    r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '466568-999' } }, r);
    assert.strictEqual(r.code, 404); assert.strictEqual(r.body.code, 'TARJA_NO_ENCONTRADA');
    r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '900000-1' } }, r);
    assert.strictEqual(r.code, 404); assert.strictEqual(r.body.code, 'TARJA_SIN_REGISTRO_PRODUCCION');
    state.fps.ok = false;
    const restore = quiet();
    r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '466568-1' } }, r);
    restore();
    assert.strictEqual(r.code, 503); assert.strictEqual(r.body.code, 'FPS_NO_DISPONIBLE');
});

test('tarja: número de registro solo (0, 1 o varias etiquetas)', async () => {
    reset();
    state.etiquetasDeRegistro['777'] = [];
    state.etiquetasDeRegistro['466568'] = [{ codigo: '466568-1', n_etiqueta: 1, cantidad: 0 }];
    state.etiquetasDeRegistro['555'] = [{ codigo: '555-1', n_etiqueta: 1, cantidad: 10 }, { codigo: '555-2', n_etiqueta: 2, cantidad: 0 }];
    let r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '777' } }, r);
    assert.strictEqual(r.code, 404);
    r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '466568' } }, r);
    assert.strictEqual(r.body.data.codigo, '466568-1');
    r = mkRes(); await pallets.obtenerTarja({ params: { codigo: '555' } }, r);
    assert.strictEqual(r.body.data.requiereEtiqueta, true);
    assert.deepStrictEqual(r.body.data.etiquetas, [{ codigo: '555-1', nEtiqueta: 1, cantidad: 10 }, { codigo: '555-2', nEtiqueta: 2, cantidad: null }]);
});

// ---------------- Guardado junto con la inspección ----------------
test('REGRESIÓN: inspección sin clasificaciones = comportamiento anterior (sin consultas de pallets, sin campo nuevo)', async () => {
    reset();
    const res = await guardar({ ...base });
    assert.strictEqual(res.code, 201);
    assert.deepStrictEqual(Object.keys(res.body.data).sort(), ['estadoId', 'registroId']);
    assert.strictEqual(palletCalls().length, 0);
    assert.ok(!calls.some((c) => c.text && /SAVE TRANSACTION/.test(c.text)));
    assert.ok(calls.includes('COMMIT'));
});

test('uno o varios pallets, con los tres colores, en la misma transacción que la inspección', async () => {
    reset();
    const res = await guardar({
        ...base,
        pallets: [
            { codigo: '466568-1', color: 'azul', defectos: [1, 2], observacion: '  revisar descalse ' },
            { codigo: '466568-2', color: 'ROJO', defectos: [3] },
            { codigo: '466568-3', color: 'VERDE' },
        ],
    });
    assert.strictEqual(res.code, 201);
    assert.deepStrictEqual(res.body.data.pallets.guardados.map((g) => g.color), ['AZUL', 'ROJO', 'VERDE']);
    assert.deepStrictEqual(res.body.data.pallets.ignorados, []);
    const orden = calls.map((c) => (typeof c === 'string' ? c : /INSERT INTO registros_control/.test(c.text) ? 'REGISTRO' : /INSERT INTO pallet_clasificaciones/.test(c.text) ? 'PALLET' : /pallet_clasificacion_defectos/.test(c.text) ? 'DEFECTO' : null)).filter(Boolean);
    assert.deepStrictEqual(orden, ['BEGIN', 'REGISTRO', 'PALLET', 'DEFECTO', 'DEFECTO', 'PALLET', 'DEFECTO', 'PALLET', 'COMMIT']);
    const p1 = inserts()[0].p;
    assert.strictEqual(p1.registroId, 99);
    assert.strictEqual(p1.observacion, 'revisar descalse');
    assert.strictEqual(p1.fpsVerificado, true);
    assert.strictEqual(p1.ordenFabricacion, '22669');
    assert.strictEqual(p1.maquinaFps, 'BOBST 142 - 2 (SFM)');
    assert.strictEqual(p1.cantidad, null);
    assert.strictEqual(inserts()[1].p.cantidad, 1200);
});

test('observación, foto y defectos son opcionales: VERDE pelado se guarda', async () => {
    reset();
    const res = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'VERDE' }] });
    assert.strictEqual(res.code, 201);
    const p = inserts()[0].p;
    assert.strictEqual(p.observacion, null);
    assert.strictEqual(p.fotoRuta, null);
    assert.strictEqual(res.body.data.pallets.guardados.length, 1);
});

test('foto del pallet: se asocia por índice y se guarda su ruta; las no usadas se borran', async () => {
    reset();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pal-'));
    const mk = (n) => { const p = path.join(dir, n); fs.writeFileSync(p, 'x'); return { filename: n, originalname: n, path: p, mimetype: 'image/jpeg', size: 1 }; };
    const f0 = mk('a.jpg'); const f1 = mk('b.jpg');
    const res = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'ROJO', fotoIndex: 0 }, { codigo: 'MALO', color: 'ROJO', fotoIndex: 1 }] },
        { fotosPallet: [f0, f1], files: [f0, f1] });
    assert.strictEqual(res.code, 201);
    assert.strictEqual(inserts()[0].p.fotoRuta, '/uploads/control/a.jpg');
    assert.ok(fs.existsSync(f0.path), 'la foto usada se conserva');
    assert.ok(!fs.existsSync(f1.path), 'la foto del pallet descartado se borra');
    fs.rmSync(dir, { recursive: true, force: true });
});

test('pallets inválidos no bloquean la inspección: se descartan con motivo', async () => {
    reset();
    const res = await guardar({
        ...base,
        pallets: [
            { codigo: '466568-1', color: 'AMARILLO' },
            { codigo: 'ABC', color: 'AZUL' },
            { codigo: '466568-999', color: 'AZUL' },
            { codigo: '466568-1', color: 'VERDE' },
            { codigo: '466568-1', color: 'ROJO' },
            null,
        ],
    });
    assert.strictEqual(res.code, 201);
    assert.deepStrictEqual(res.body.data.pallets.guardados.map((g) => g.codigo), ['466568-1']);
    assert.deepStrictEqual(res.body.data.pallets.ignorados.map((i) => i.motivo),
        ['COLOR_INVALIDO', 'CODIGO_INVALIDO', 'TARJA_NO_ENCONTRADA', 'REPETIDO_EN_LA_INSPECCION', 'COLOR_INVALIDO']);
    assert.ok(calls.includes('COMMIT'));
});

test('defectos ajenos al proceso se descartan sin error', async () => {
    reset();
    const res = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'AZUL', defectos: [1, 999, 'x', 1] }] });
    assert.strictEqual(res.code, 201);
    const defectos = calls.filter((c) => c.text && /INSERT INTO pallet_clasificacion_defectos/.test(c.text));
    assert.deepStrictEqual(defectos.map((d) => d.p.parametroId), [1]);
});

test('error de FPS: la inspección se guarda y el pallet queda con los datos de la app, no verificado', async () => {
    reset(); state.fps.ok = false;
    const res = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'AZUL', datosFps: { ordenFabricacion: '22669', cliente: 'CLIENTE APP', maquina: 'BOBST', fechaTarja: '2026-11-22T21:08:49' } }] });
    assert.strictEqual(res.code, 201);
    const p = inserts()[0].p;
    assert.strictEqual(p.fpsVerificado, false);
    assert.strictEqual(p.cliente, 'CLIENTE APP');
    assert.strictEqual(p.maquinaFps, 'BOBST');
    assert.ok(calls.includes('COMMIT'));
});

test('fallo al guardar clasificaciones (p. ej. migración 015 pendiente): se deshace solo eso y la inspección se confirma', async () => {
    reset(); state.fallaInsertPallet = true;
    const res = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'AZUL' }] });
    assert.strictEqual(res.code, 201);
    assert.deepStrictEqual(res.body.data.pallets.guardados, []);
    assert.strictEqual(res.body.data.pallets.ignorados[0].motivo, 'ERROR_AL_GUARDAR');
    assert.ok(calls.some((c) => c.text && /ROLLBACK TRANSACTION pallets_clasificacion/.test(c.text)));
    assert.ok(calls.includes('COMMIT'));
    assert.ok(!calls.includes('ROLLBACK'));
});

test('idempotencia: reintento con el mismo clientId devuelve 200 duplicado y NO reinserta pallets', async () => {
    reset(); state.uuidExistente = 42;
    const res = await guardar({ ...base, clientId: 'abcdef12-3456', pallets: [{ codigo: '466568-1', color: 'AZUL' }] });
    assert.strictEqual(res.code, 200);
    assert.strictEqual(res.body.duplicado, true);
    assert.strictEqual(inserts().length, 0);
    assert.ok(!calls.includes('BEGIN'));
});

test('reclasificación: cada clasificación es un evento nuevo; nunca se actualiza ni borra el historial', async () => {
    reset();
    await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'AZUL' }] });
    await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'VERDE' }] });
    assert.strictEqual(inserts().length, 2);
    assert.deepStrictEqual(inserts().map((i) => i.p.color), ['AZUL', 'VERDE']);
    assert.ok(!calls.some((c) => c.text && /(UPDATE|DELETE)\s+(FROM\s+)?pallet_clasificaciones/i.test(c.text)));
});

// ---------------- Lectura y anulación (Photino) ----------------
test('filtros: todo va parametrizado, valores inválidos se ignoran', () => {
    const f = pallets.construirFiltros({ desde: '2026-11-01', hasta: '2026-11-30', color: 'rojo', procesoId: '3', operador: "x' OR 1=1 --", np: '3957', defectoId: '5', vista: 'vigentes', maquinaId: 'abc' });
    assert.ok(!/x' OR/.test(f.where) && !/2026-11/.test(f.where), 'ningún valor viaja dentro del SQL');
    assert.deepStrictEqual(f.inputs.map((i) => i[0]).sort(), ['color', 'defectoId', 'desde', 'hasta', 'np', 'operador', 'procesoId']);
    assert.ok(/b\.vigente = 1/.test(f.where));
    const malo = pallets.construirFiltros({ desde: 'ayer', color: 'NEGRO', procesoId: '-1' });
    assert.deepStrictEqual(malo.inputs.map((i) => i[0]), []);
});

test('anular: exige motivo, es lógica (UPDATE de marca) y registra quién', async () => {
    reset();
    let r = mkRes(); await pallets.anularClasificacion({ params: { id: '5' }, body: {} }, r);
    assert.strictEqual(r.code, 400); assert.strictEqual(r.body.code, 'MOTIVO_REQUERIDO');
    r = mkRes(); const restore = quiet();
    await pallets.anularClasificacion({ params: { id: '5' }, body: { motivo: 'Pallet equivocado' }, auth: { nombre: 'Calidad Uno' } }, r);
    restore();
    const upd = calls.find((c) => c.text && /UPDATE pallet_clasificaciones/.test(c.text));
    assert.ok(upd && /anulado = 1/.test(upd.text) && !/DELETE/i.test(upd.text));
    assert.strictEqual(upd.p.motivo, 'Pallet equivocado');
    assert.strictEqual(upd.p.por, 'Calidad Uno');
});

// ---------------- Migración y aislamiento de FARET ----------------
test('migración 015: aditiva (solo tablas nuevas); rollback solo borra las tablas nuevas', () => {
    const dir = path.join(__dirname, '..', 'migrations');
    const up = fs.readFileSync(path.join(dir, '015_clasificacion_pallets.sql'), 'utf8').replace(/--.*$/gm, '').replace(/GRANT[^;]*;/gi, '');
    const down = fs.readFileSync(path.join(dir, '015_clasificacion_pallets_rollback.sql'), 'utf8').replace(/--.*$/gm, '');
    assert.ok(!/\b(DROP|DELETE|TRUNCATE|UPDATE)\b/i.test(up), 'la migración no destruye ni modifica datos');
    assert.ok(!/ALTER\s+TABLE/i.test(up), 'no altera tablas existentes');
    assert.deepStrictEqual([...up.matchAll(/CREATE TABLE\s+dbo\.(\w+)/gi)].map((m) => m[1]).sort(), ['pallet_clasificacion_defectos', 'pallet_clasificaciones']);
    assert.deepStrictEqual([...down.matchAll(/DROP TABLE\s+dbo\.(\w+)/gi)].map((m) => m[1]).sort(), ['pallet_clasificacion_defectos', 'pallet_clasificaciones']);
    assert.ok(/CHECK \(color IN \(N'AZUL', N'ROJO', N'VERDE'\)\)/.test(up));
});

test('FARET intacto: ningún archivo de FARET referencia la clasificación de pallets', () => {
    const src = path.join(__dirname, '..', 'src');
    for (const f of ['controllers/calidadFaret.controller.js', 'routes/calidadFaret.routes.js', 'controllers/calidadFaretPallet.controller.js', 'routes/calidadFaretPallet.routes.js', 'controllers/calidadFaretOperadores.controller.js']) {
        const t = fs.readFileSync(path.join(src, f), 'utf8');
        assert.ok(!/clasificacionPallets|pallet_clasificaciones|fotosPallet/.test(t), `${f} no debe tocar la clasificación de pallets INNPACK`);
    }
});
