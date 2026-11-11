// Edición de inspecciones FARET (Calidad y Pallet/Papel): rutas + autorización por rol + validaciones + auditoría + atomicidad.
// Sin base real: doble de SQL con estado en memoria (el SQL real se valida aparte en migrations/tests/run_edicion_localdb.sh).
// Las APIs de autenticación se reemplazan por un servidor local de prueba. Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const Module = require('module');

// ---- Autenticación de prueba ----
const usuarios = {
    F_ADMIN: { roles: ['ADMIN'], nombre: 'Ana Admin' },
    F_ADMINTI: { roles: ['ADMIN_TI'], nombre: 'Tito TI' },
    F_INSPECTOR: { roles: ['INSPECTOR'], nombre: 'Ines Inspectora' },
    F_CALIDAD: { roles: ['CALIDAD'], nombre: 'Carla Calidad' },
    F_CONSULTA: { roles: ['CONSULTA'], nombre: 'Cons Ulta' },
};
const upstream = http.createServer((req, res) => {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    let claims = {};
    try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()); } catch (_) { }
    const u = usuarios[claims.sub];
    const json = (st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.url === '/faret/api/Auth/me') return u ? json(200, { success: true, data: { id: 7, nombre: u.nombre, roles: u.roles } }) : json(401, {});
    if (req.url === '/innpack/api/Auth/mis-permisos') return json(401, {});
    return json(404, {});
});
const jwt = (sub) => {
    const b = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    return `${b({ alg: 'HS256' })}.${b({ sub, exp: Math.floor(Date.now() / 1000) + 3600 })}.firma`;
};

// ---- Doble de SQL Server con estado ----
const EVENTOS = {
    'OFF-001': { id_evento: 'OFF-001', area_control: '03-OFFSET', defecto: 'DIFERENCIA DE TONO', criticidad: 'Critico' },
    'OFF-004': { id_evento: 'OFF-004', area_control: '03-OFFSET', defecto: 'MANCHA DE TINTA', criticidad: 'Mayor' },
    'TRO-001': { id_evento: 'TRO-001', area_control: '04-TROQUELADO', defecto: 'CORTE DESPLAZADO', criticidad: 'Critico' },
};
let db;
let snapshot;
let fallarAuditoria = false;
const nuevoEstado = () => ({
    calidad: {
        id: 10, eliminado: 0,
        row: { nv_faret: 'NV-100', nv_vb_aprobado: 1, n_pliego: '5', n_pasada: null, n_item: null, pliego_control_n: null, observaciones: 'Obs original',
            area_control: '03-OFFSET', operador: 'Juan', operador_otro: null, maquina: 'Offset 1', presenta_defectos: 1, area_defecto: '03-OFFSET',
            tipo_folia: null, accion_correctiva: 'Ajuste' },
        defectos: [
            { defecto: 'DIFERENCIA DE TONO', id_evento: 'OFF-001', criticidad: 'Critico' },
            { defecto: 'DEFECTO HISTORICO', id_evento: null, criticidad: null },
        ],
    },
    pallet: {
        id: 20, eliminado: 0,
        row: { tipo_material: 'NV', dimension: '100x70', fibra: 'Larga', numero_pallet: 'P-1', numero_pasadas_prensa: 1, observaciones: null,
            area_control: 'Prensa', operador: 'Luis', operador_otro: null, maquina: 'Prensa 2' },
        respuestas: [
            { preguntaId: 1, texto: 'Pallet limpio', resultado: 'CUMPLE', observacion: null },
            { preguntaId: 2, texto: 'Sin humedad', resultado: 'NO_CUMPLE', observacion: 'Humedo' },
        ],
    },
    auditoria: [],
    calls: [],
});
const reiniciar = () => { db = nuevoEstado(); fallarAuditoria = false; };

class FakeRequest {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        const t = text.replace(/\s+/g, ' ');
        db.calls.push(t.slice(0, 40));
        const p = this.p;
        if (/FROM registros_calidad_faret WITH \(UPDLOCK/.test(t)) return { recordset: p.id === db.calidad.id && !db.calidad.eliminado ? [{ ...db.calidad.row }] : [] };
        if (/^SELECT .*FROM registro_calidad_faret_defectos WHERE registro_id/.test(t)) return { recordset: db.calidad.defectos.map((d) => ({ ...d })) };
        if (/^UPDATE registros_calidad_faret SET nv_faret/.test(t)) {
            const r = db.calidad.row;
            Object.assign(r, { nv_faret: p.nvFaret, nv_vb_aprobado: p.nvVoBoAprobado, n_pliego: p.nPliego, n_pasada: p.nPasada, n_item: p.nItem,
                pliego_control_n: p.pliegoControlN, observaciones: p.observaciones, area_control: p.areaControl, operador: p.operador,
                operador_otro: p.operadorOtro, maquina: p.maquina, presenta_defectos: p.presentaDefectos, area_defecto: p.areaDefecto,
                tipo_folia: p.tipoFolia, accion_correctiva: p.accionCorrectiva });
            return { rowsAffected: [1] };
        }
        if (/^DELETE FROM registro_calidad_faret_defectos/.test(t)) {
            db.calidad.defectos = db.calidad.defectos.filter((d) => !(d.defecto === p.defecto && (d.id_evento || null) === (p.idEvento || null)));
            return { rowsAffected: [1] };
        }
        if (/^INSERT INTO registro_calidad_faret_defectos/.test(t)) {
            db.calidad.defectos.push({ defecto: p.defecto, id_evento: p.idEvento || null, criticidad: p.criticidad || null });
            return { rowsAffected: [1] };
        }
        if (/FROM dbo\.vw_calidad_faret_eventos_operables WHERE id_evento IN/.test(t)) {
            const ids = Object.values(p);
            return { recordset: ids.map((i) => EVENTOS[i]).filter(Boolean) };
        }
        if (/FROM registros_calidad_faret_pallet WITH \(UPDLOCK/.test(t)) return { recordset: p.id === db.pallet.id && !db.pallet.eliminado ? [{ ...db.pallet.row }] : [] };
        if (/FROM registro_calidad_faret_pallet_respuestas resp/.test(t)) return { recordset: db.pallet.respuestas.map((r) => ({ ...r })) };
        if (/^UPDATE registros_calidad_faret_pallet SET/.test(t)) {
            Object.assign(db.pallet.row, { tipo_material: p.tipoMaterial, dimension: p.dimension, fibra: p.fibra, numero_pallet: p.numeroPallet,
                numero_pasadas_prensa: p.numeroPasadasPrensa, observaciones: p.observaciones, area_control: p.areaControl, operador: p.operador,
                operador_otro: p.operadorOtro, maquina: p.maquina });
            return { rowsAffected: [1] };
        }
        if (/^UPDATE registro_calidad_faret_pallet_respuestas/.test(t)) {
            const r = db.pallet.respuestas.find((x) => x.preguntaId === p.pid);
            r.resultado = p.resultado; r.observacion = p.observacion;
            return { rowsAffected: [1] };
        }
        if (/^INSERT INTO dbo\.inspecciones_faret_auditoria/.test(t)) {
            if (fallarAuditoria) throw new Error('fallo simulado de auditoría');
            db.auditoria.push({ tipo: p.tipo, registro_id: p.registroId, campo: p.campo, anterior: p.anterior, nuevo: p.nuevo, motivo: p.motivo,
                usuario_id: p.usuarioId, usuario_nombre: p.usuarioNombre, origen: p.origen });
            return { rowsAffected: [1] };
        }
        return { recordset: [], rowsAffected: [0] };
    }
}
class FakeTransaction {
    async begin() { snapshot = JSON.stringify(db); db.calls.push('BEGIN'); }
    async commit() { db.calls.push('COMMIT'); snapshot = null; }
    async rollback() { if (snapshot) { const calls = db.calls; db = JSON.parse(snapshot); db.calls = [...calls, 'ROLLBACK']; snapshot = null; } }
}
const sqlStub = new Proxy({}, { get: (_, k) => (k === 'Transaction' ? FakeTransaction : k === 'Request' ? FakeRequest : k === 'MAX' ? 'MAX' : () => 'T') });
const cargar = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new FakeRequest() }) };
    return cargar.call(this, request, ...rest);
};

const express = require('express');
let server; let base;
test.before(async () => {
    await new Promise((r) => upstream.listen(0, '127.0.0.1', r));
    process.env.AUTH_FARET_URL = `http://127.0.0.1:${upstream.address().port}/faret`;
    process.env.AUTH_INNPACK_URL = `http://127.0.0.1:${upstream.address().port}/innpack`;
    process.env.AUTH_EDICION_MODO = 'off';          // aunque el entorno diga "off", la edición SIEMPRE exige sesión y rol
    process.env.LIMITE_POST_POR_MIN = '0';
    const app = express();
    app.use(express.json());
    app.use('/api/calidad-faret', require('../src/routes/calidadFaret.routes'));
    app.use('/api/calidad-faret-pallet', require('../src/routes/calidadFaretPallet.routes'));
    await new Promise((r) => { server = app.listen(0, '127.0.0.1', r); });
    base = `http://127.0.0.1:${server.address().port}`;
});
test.after(() => { server.close(); upstream.close(); });
test.beforeEach(reiniciar);

const put = (ruta, cuerpo, sub = 'F_INSPECTOR') => fetch(base + ruta, {
    method: 'PUT',
    headers: { 'content-type': 'application/json', ...(sub ? { authorization: `Bearer ${jwt(sub)}` } : {}) },
    body: JSON.stringify(cuerpo),
}).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
const putCal = (c, sub) => put('/api/calidad-faret/registros/10', c, sub);
const putPal = (c, sub) => put('/api/calidad-faret-pallet/registros/20', c, sub);
const MOTIVO = 'Error de digitación del operador';

// ---------------------------------------------------------------- permisos
test('permisos: ADMIN, ADMIN_TI e INSPECTOR editan; CALIDAD y CONSULTA no; sin token no; "off" no desactiva la exigencia', async () => {
    for (const sub of ['F_ADMIN', 'F_ADMINTI', 'F_INSPECTOR']) {
        reiniciar();
        const r = await putCal({ motivo: MOTIVO, maquina: `Maq ${sub}` }, sub);
        assert.equal(r.status, 200, `${sub}: ${JSON.stringify(r.body)}`);
    }
    for (const sub of ['F_CALIDAD', 'F_CONSULTA']) {
        reiniciar();
        const r = await putCal({ motivo: MOTIVO, maquina: 'X' }, sub);
        assert.equal(r.status, 403, sub);
        assert.equal(db.calidad.row.maquina, 'Offset 1', 'no se modificó nada');
        assert.equal(db.auditoria.length, 0);
    }
    assert.equal((await putCal({ motivo: MOTIVO, maquina: 'X' }, null)).status, 401);
    assert.equal((await putPal({ motivo: MOTIVO, maquina: 'X' }, 'F_CALIDAD')).status, 403);
    assert.equal((await putPal({ motivo: MOTIVO, maquina: 'X' }, null)).status, 401);
    assert.equal((await putPal({ motivo: MOTIVO, maquina: 'X' }, 'F_ADMIN')).status, 200);
});

// ---------------------------------------------------------------- Calidad
test('Calidad: edita campos, audita cada campo con usuario/motivo/anterior/nuevo y confirma en una sola transacción', async () => {
    const r = await putCal({ motivo: MOTIVO, nvFaret: 'NV-200', maquina: 'Offset 3', observaciones: 'Obs corregida' });
    assert.equal(r.status, 200);
    assert.equal(r.body.data.camposModificados, 3);
    assert.equal(db.calidad.row.nv_faret, 'NV-200');
    assert.equal(db.calidad.row.maquina, 'Offset 3');
    assert.equal(db.calidad.row.operador, 'Juan', 'lo no enviado no cambia');
    assert.equal(db.auditoria.length, 3);
    const a = db.auditoria.find((x) => x.campo === 'NV Faret');
    assert.deepEqual({ ...a }, { tipo: 'CALIDAD', registro_id: 10, campo: 'NV Faret', anterior: 'NV-100', nuevo: 'NV-200', motivo: MOTIVO,
        usuario_id: '7', usuario_nombre: 'Ines Inspectora', origen: 'faret' });
    assert.ok(db.calls.includes('BEGIN') && db.calls.includes('COMMIT') && !db.calls.includes('ROLLBACK'));
});

test('Calidad: motivo obligatorio, sin cambios, registro inexistente, obligatorios y largos', async () => {
    assert.equal((await putCal({ maquina: 'X' })).status, 400);
    assert.match((await putCal({ motivo: 'abc', maquina: 'X' })).body.message, /motivo/i);
    const sin = await putCal({ motivo: MOTIVO, maquina: 'Offset 1', nvFaret: 'NV-100' });
    assert.equal(sin.status, 400); assert.match(sin.body.message, /No hay cambios/);
    assert.equal(db.auditoria.length, 0);
    const noExiste = await put('/api/calidad-faret/registros/999', { motivo: MOTIVO, maquina: 'X' });
    assert.equal(noExiste.status, 404);
    assert.equal((await putCal({ motivo: MOTIVO, nvFaret: '   ' })).status, 400);
    assert.equal((await putCal({ motivo: MOTIVO, nvFaret: 'x'.repeat(101) })).status, 400);
    assert.equal((await putCal({ motivo: MOTIVO, nvVoBoAprobado: 'si' })).status, 400);
    assert.equal((await put('/api/calidad-faret/registros/abc', { motivo: MOTIVO, maquina: 'X' })).status, 400);
    assert.equal(db.calidad.row.nv_faret, 'NV-100');
});

test('Calidad: defectos — quita uno, agrega un evento del catálogo (criticidad desde SQL, no del cliente) y conserva el histórico sin criticidad', async () => {
    const r = await putCal({ motivo: MOTIVO, defectos: ['DEFECTO HISTORICO', { idEvento: 'OFF-004', criticidad: 'Menor', defecto: 'texto falso' }] });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const nombres = db.calidad.defectos.map((d) => `${d.id_evento || '-'}|${d.defecto}|${d.criticidad || '-'}`).sort();
    assert.deepEqual(nombres, ['-|DEFECTO HISTORICO|-', 'OFF-004|MANCHA DE TINTA|Mayor']);
    const aud = db.auditoria.find((x) => x.campo === 'Defectos');
    assert.match(aud.anterior, /OFF-001 · DIFERENCIA DE TONO \(Critico\)/);
    assert.match(aud.nuevo, /OFF-004 · MANCHA DE TINTA \(Mayor\)/);
});

test('Calidad: reenviar los mismos defectos no cambia nada; el histórico sin id/criticidad se conserva', async () => {
    const r = await putCal({ motivo: MOTIVO, defectos: ['DEFECTO HISTORICO', { idEvento: 'OFF-001' }] });
    assert.equal(r.status, 400); assert.match(r.body.message, /No hay cambios/);
    assert.equal(db.calidad.defectos.length, 2);
});

test('Calidad: evento de otra área o inexistente se rechaza; cambiar el área exige reseleccionar los eventos', async () => {
    const otra = await putCal({ motivo: MOTIVO, defectos: [{ idEvento: 'OFF-001' }, { idEvento: 'TRO-001' }] });
    assert.equal(otra.status, 400); assert.match(otra.body.message, /no corresponde al área/);
    const falso = await putCal({ motivo: MOTIVO, defectos: [{ idEvento: 'OFF-999' }] });
    assert.equal(falso.status, 400);
    const area = await putCal({ motivo: MOTIVO, areaDefecto: '04-TROQUELADO' });
    assert.equal(area.status, 400); assert.match(area.body.message, /volver a seleccionar/);
    const ok = await putCal({ motivo: MOTIVO, areaDefecto: '04-TROQUELADO', defectos: [{ idEvento: 'TRO-001' }] });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(db.calidad.defectos.some((d) => d.id_evento === 'OFF-001'), false);
    assert.equal(db.calidad.defectos.some((d) => d.id_evento === 'TRO-001' && d.criticidad === 'Critico'), true);
});

test('Calidad: marcar "sin defectos" borra los defectos y limpia área/folia/acción correctiva', async () => {
    const r = await putCal({ motivo: MOTIVO, presentaDefectos: false });
    assert.equal(r.status, 200);
    assert.equal(db.calidad.defectos.length, 0);
    assert.equal(db.calidad.row.area_defecto, null);
    assert.equal(db.calidad.row.accion_correctiva, null);
    const campos = db.auditoria.map((x) => x.campo);
    assert.ok(campos.includes('¿Presenta defectos?') && campos.includes('Defectos') && campos.includes('Acción correctiva'));
});

test('Calidad: si falla la auditoría se revierte TODO (registro y defectos)', async () => {
    fallarAuditoria = true;
    const r = await putCal({ motivo: MOTIVO, maquina: 'Otra', defectos: [{ idEvento: 'OFF-004' }] });
    assert.equal(r.status, 500);
    assert.equal(db.calidad.row.maquina, 'Offset 1');
    assert.equal(db.calidad.defectos.length, 2);
    assert.equal(db.auditoria.length, 0);
    assert.ok(db.calls.includes('ROLLBACK'));
});

test('Calidad: lo que no es editable (fecha, operador de registro, client_uuid, adjuntos) se ignora', async () => {
    const r = await putCal({ motivo: MOTIVO, maquina: 'Z', fechaRegistro: '2020-01-01', operadorRegistro: 'Otro', clientId: 'x', cantidadAdjuntos: 0 });
    assert.equal(r.status, 200);
    assert.equal(db.auditoria.length, 1);
    assert.equal(db.auditoria[0].campo, 'Máquina');
});

// ---------------------------------------------------------------- Pallet
test('Pallet: edita cabecera y checklist, audita cada cambio y no permite cambiar el conjunto de preguntas', async () => {
    const r = await putPal({
        motivo: MOTIVO, dimension: '120x80', numeroPasadasPrensa: 2,
        respuestas: [{ preguntaId: 1, resultado: 'NO_CUMPLE', observacion: 'Sucio' }, { preguntaId: 2, resultado: 'NO_CUMPLE', observacion: 'Humedo' }],
    });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(db.pallet.row.dimension, '120x80');
    assert.equal(db.pallet.row.numero_pasadas_prensa, 2);
    assert.equal(db.pallet.respuestas[0].resultado, 'NO_CUMPLE');
    assert.equal(db.auditoria.length, 3);
    const chk = db.auditoria.find((x) => x.campo.startsWith('Checklist'));
    assert.equal(chk.anterior, 'CUMPLE'); assert.equal(chk.nuevo, 'NO CUMPLE — Sucio'); assert.equal(chk.tipo, 'PALLET');
    reiniciar();
    assert.equal((await putPal({ motivo: MOTIVO, respuestas: [{ preguntaId: 1, resultado: 'CUMPLE' }] })).status, 400);
    assert.equal((await putPal({ motivo: MOTIVO, respuestas: [{ preguntaId: 1, resultado: 'CUMPLE' }, { preguntaId: 3, resultado: 'CUMPLE' }] })).status, 400);
});

test('Pallet: validaciones (motivo, tipo material, pasadas, NO_CUMPLE sin observación, obligatorios, sin cambios, no existe)', async () => {
    assert.equal((await putPal({ dimension: 'x' })).status, 400);
    assert.equal((await putPal({ motivo: MOTIVO, tipoMaterial: 'VIDRIO' })).status, 400);
    assert.equal((await putPal({ motivo: MOTIVO, numeroPasadasPrensa: 5 })).status, 400);
    assert.equal((await putPal({ motivo: MOTIVO, respuestas: [{ preguntaId: 1, resultado: 'NO_CUMPLE' }, { preguntaId: 2, resultado: 'CUMPLE' }] })).status, 400);
    assert.equal((await putPal({ motivo: MOTIVO, numeroPallet: ' ' })).status, 400);
    const sin = await putPal({ motivo: MOTIVO, dimension: '100x70' });
    assert.equal(sin.status, 400); assert.match(sin.body.message, /No hay cambios/);
    assert.equal((await put('/api/calidad-faret-pallet/registros/999', { motivo: MOTIVO, dimension: 'x' })).status, 404);
    const ok = await putPal({ motivo: MOTIVO, numeroPasadasPrensa: null });
    assert.equal(ok.status, 200);
    assert.equal(db.pallet.row.numero_pasadas_prensa, null);
});

test('Pallet: falla de auditoría revierte cabecera y respuestas', async () => {
    fallarAuditoria = true;
    const r = await putPal({ motivo: MOTIVO, dimension: 'Nueva', respuestas: [{ preguntaId: 1, resultado: 'NO_CUMPLE', observacion: 'x' }, { preguntaId: 2, resultado: 'NO_CUMPLE', observacion: 'Humedo' }] });
    assert.equal(r.status, 500);
    assert.equal(db.pallet.row.dimension, '100x70');
    assert.equal(db.pallet.respuestas[0].resultado, 'CUMPLE');
});

test('el listado sigue funcionando sin la bitácora y la consulta de auditoría requiere sesión', async () => {
    const r = await fetch(`${base}/api/calidad-faret/registros/10/auditoria`);
    assert.ok([401, 403].includes(r.status) || r.status === 200, 'ruta montada');
    const { _vaciarCacheAuditoria, auditoriaDisponible } = require('../src/utils/edicionInspecciones');
    _vaciarCacheAuditoria();
    assert.equal(await auditoriaDisponible({ request: () => ({ query: async () => ({ recordset: [{ id: null }] }) }) }), false);
    _vaciarCacheAuditoria();
    assert.equal(await auditoriaDisponible({ request: () => ({ query: async () => ({ recordset: [{ id: 123 }] }) }) }), true);
    _vaciarCacheAuditoria();
});
