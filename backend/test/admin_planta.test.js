// Administración de planta: autorización por rol, validaciones, duplicados, alta/baja/edición con auditoría y atomicidad.
// Sin base real: doble de SQL con estado en memoria (el SQL real de la migración se valida con LocalDB, ver migrations/013_*).
// Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const http = require('http');
const Module = require('module');

// Sesiones FARET (F_*): las valida /faret/api/Auth/me. Sesiones INNPACK (I_*): /innpack/api/Auth/mis-permisos, rol y nombre del JWT.
const usuarios = {
    F_ADMINTI: { roles: ['ADMIN_TI'], nombre: 'Tito TI' },
    F_CONSULTA: { roles: ['CONSULTA'], nombre: 'Cons Ulta' },
};
const sesionesInnpack = {
    I_ADMINTI: { role: 'admin_ti', name: 'Tito TI' },
    I_CALIDAD: { role: 'calidad', name: 'Cali Dad' },
};
const upstream = http.createServer((req, res) => {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    let claims = {};
    try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()); } catch (_) { }
    const u = usuarios[claims.sub];
    const json = (st, o) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.url === '/faret/api/Auth/me') return u ? json(200, { success: true, data: { id: 7, nombre: u.nombre, roles: u.roles } }) : json(401, {});
    if (req.url === '/innpack/api/Auth/mis-permisos') return sesionesInnpack[claims.sub] ? json(200, { ok: true }) : json(401, {});
    return json(401, {});
});
const jwt = (sub) => {
    const b = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    return `${b({ alg: 'HS256' })}.${b({ sub, ...sesionesInnpack[sub], exp: Math.floor(Date.now() / 1000) + 3600 })}.firma`;
};

// ---- Doble de SQL Server (INNPACK: procesos + maquinas) ----
let db;
const nuevoDb = () => ({
    procesos: [{ id: 4, nombre: 'Pegado' }, { id: 5, nombre: 'Troquelado' }],
    maquinas: [{ id: 1, nombre: 'Diana VIII', codigo_qr: 'MAQ-PEG-DIANA', proceso_id: 4, activo: true }],
    usuarios: [
        { id: 10, nombre_completo: 'Ana Inspectora', codigo_usuario: 'CAL-AINSPECTORA', rol: 'operador', activo: true, oculto: false },
        { id: 11, nombre_completo: 'Servicio Tecnico', codigo_usuario: 'SVC-TEC', rol: 'operador', activo: true, oculto: true },
    ],
    auditoria: [], sig: 2, fallarAuditoria: false,
});
const filaUsuario = (u) => ({ id: u.id, nombre: u.nombre_completo, activo: u.activo, oculto: u.oculto, codigo: u.codigo_usuario });
const proceso = (id) => db.procesos.find((x) => x.id === id);
const fila = (m) => ({ id: m.id, nombre: m.nombre, activo: m.activo, codigo: m.codigo_qr, grupoId: m.proceso_id, grupo: proceso(m.proceso_id)?.nombre });
let snapshot;
class FakeRequest {
    constructor() { this.p = {}; }
    input(n, _t, v) { this.p[n] = v; return this; }
    async query(t) {
        t = t.replace(/\s+/g, ' ').trim();
        const p = this.p;
        if (/^SELECT t\.id AS id.* FROM dbo\.maquinas t/.test(t)) {
            const l = db.maquinas.filter((m) => p.id === undefined || m.id === p.id);
            return { recordset: l.map(fila) };
        }
        if (/^SELECT t\.id AS id.* FROM dbo\.usuarios t/.test(t)) {
            const verOcultos = !t.includes('t.oculto = 0');
            const l = db.usuarios.filter((u) => (p.id === undefined || u.id === p.id) && (verOcultos || !u.oculto));
            return { recordset: l.map(filaUsuario) };
        }
        if (/FROM dbo\.usuarios t WHERE t\.nombre_completo/.test(t)) {
            const dup = db.usuarios.some((u) => u.nombre_completo.toLowerCase() === p.nombre.toLowerCase() && u.id !== p.excluir);
            return { recordset: dup ? [{ x: 1 }] : [] };
        }
        if (/^UPDATE dbo\.usuarios SET/.test(t)) {
            const u = db.usuarios.find((x) => x.id === p.id);
            if (p.nombre !== undefined) u.nombre_completo = p.nombre;
            if (p.activo !== undefined) u.activo = !!p.activo;
            return { rowsAffected: [1] };
        }
        if (/^SELECT nombre FROM dbo\.procesos WHERE id = @g/.test(t)) return { recordset: [{ nombre: proceso(p.g).nombre }] };
        if (/FROM dbo\.procesos WHERE id = @g/.test(t)) return { recordset: proceso(p.g) ? [{ x: 1 }] : [] };
        if (/FROM dbo\.maquinas WHERE codigo_qr = @q/.test(t)) return { recordset: db.maquinas.some((m) => m.codigo_qr === p.q) ? [{ x: 1 }] : [] };
        if (/FROM dbo\.maquinas t WHERE t\.nombre/.test(t)) {
            const dup = db.maquinas.some((m) => m.nombre.toLowerCase() === p.nombre.toLowerCase() && m.proceso_id === p.grupo && m.id !== p.excluir);
            return { recordset: dup ? [{ x: 1 }] : [] };
        }
        if (/^INSERT INTO dbo\.maquinas/.test(t)) {
            const m = { id: db.sig++, nombre: p.nombre, codigo_qr: p.codigo_qr, proceso_id: p.proceso_id, activo: !!p.activo };
            db.maquinas.push(m);
            return { recordset: [{ id: m.id }] };
        }
        if (/^UPDATE dbo\.maquinas SET/.test(t)) {
            const m = db.maquinas.find((x) => x.id === p.id);
            if (p.nombre !== undefined) m.nombre = p.nombre;
            if (p.grupo !== undefined) m.proceso_id = p.grupo;
            if (p.activo !== undefined) m.activo = !!p.activo;
            return { rowsAffected: [1] };
        }
        if (/^INSERT INTO dbo\.admin_planta_auditoria/.test(t)) {
            if (db.fallarAuditoria) throw new Error('fallo simulado de auditoría');
            db.auditoria.push({ empresa: p.empresa, entidad: p.entidad, clave: p.clave, accion: p.accion, campo: p.campo, anterior: p.anterior, nuevo: p.nuevo, usuario: p.usuario });
            return { rowsAffected: [1] };
        }
        return { recordset: [], rowsAffected: [0] };
    }
}
class FakeTransaction {
    async begin() { snapshot = JSON.stringify(db); }
    async commit() { snapshot = null; }
    async rollback() { if (snapshot) { db = JSON.parse(snapshot); snapshot = null; } }
}
const sqlStub = new Proxy({}, { get: (_, k) => (k === 'Transaction' ? FakeTransaction : k === 'Request' ? FakeRequest : () => 'T') });
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
    const app = express();
    app.use(express.json());
    app.use('/api/admin-planta', require('../src/routes/adminPlanta.routes'));
    await new Promise((r) => { server = app.listen(0, '127.0.0.1', r); });
    base = `http://127.0.0.1:${server.address().port}/api/admin-planta`;
});
test.after(() => { server.close(); upstream.close(); });
test.beforeEach(() => { db = nuevoDb(); snapshot = null; });

const llamar = async (metodo, ruta, { sub = 'I_ADMINTI', cuerpo } = {}) => {
    const r = await fetch(base + ruta, {
        method: metodo,
        headers: { 'content-type': 'application/json', ...(sub ? { authorization: `Bearer ${jwt(sub)}` } : {}) },
        body: cuerpo ? JSON.stringify(cuerpo) : undefined,
    });
    return { status: r.status, body: await r.json().catch(() => null) };
};

test('sin sesión 401; rol CONSULTA 403; empresa/entidad inválida 404', async () => {
    assert.strictEqual((await llamar('GET', '/INNPACK/maquinas', { sub: null })).status, 401);
    assert.strictEqual((await llamar('GET', '/FARET/maquinas', { sub: 'F_CONSULTA' })).status, 403);
    assert.strictEqual((await llamar('GET', '/OTRA/maquinas')).status, 404);
    assert.strictEqual((await llamar('GET', '/INNPACK/nada')).status, 404);
});

test('listar devuelve máquinas con su proceso', async () => {
    const r = await llamar('GET', '/INNPACK/maquinas');
    assert.strictEqual(r.status, 200);
    assert.deepStrictEqual(r.body.data.map((m) => [m.nombre, m.grupo, m.activo]), [['Diana VIII', 'Pegado', true]]);
});

test('crear máquina: genera código QR, queda activa y auditada', async () => {
    const r = await llamar('POST', '/INNPACK/maquinas', { cuerpo: { nombre: '  Troquelado   107 ', grupoId: 5 } });
    assert.strictEqual(r.status, 201);
    assert.strictEqual(r.body.data.nombre, 'Troquelado 107');
    assert.strictEqual(r.body.data.codigo, 'MAQ-TRO-TROQUELADO107');
    assert.strictEqual(r.body.data.activo, true);
    assert.deepStrictEqual(db.auditoria.map((a) => [a.accion, a.campo, a.nuevo, a.usuario]), [['CREAR', 'nombre', 'Troquelado 107', 'Tito TI']]);
});

test('crear: nombre vacío, proceso inexistente y duplicado (sin distinguir mayúsculas)', async () => {
    assert.strictEqual((await llamar('POST', '/INNPACK/maquinas', { cuerpo: { nombre: '   ', grupoId: 4 } })).status, 400);
    assert.strictEqual((await llamar('POST', '/INNPACK/maquinas', { cuerpo: { nombre: 'Nueva' } })).status, 400);
    assert.strictEqual((await llamar('POST', '/INNPACK/maquinas', { cuerpo: { nombre: 'Nueva', grupoId: 99 } })).status, 400);
    assert.strictEqual((await llamar('POST', '/INNPACK/maquinas', { cuerpo: { nombre: 'DIANA viii', grupoId: 4 } })).status, 409);
    assert.strictEqual(db.maquinas.length, 1);
    assert.strictEqual(db.auditoria.length, 0);
});

test('baja y reactivación: auditoría por campo y sin cambios no audita', async () => {
    let r = await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { activo: false } });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.data.activo, false);
    assert.deepStrictEqual(db.auditoria.map((a) => [a.accion, a.campo, a.anterior, a.nuevo]), [['MODIFICAR', 'activo', 'Activo', 'Baja']]);
    await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { activo: false } });
    assert.strictEqual(db.auditoria.length, 1);
    r = await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { activo: true } });
    assert.strictEqual(r.body.data.activo, true);
});

test('editar nombre y mover de área; id inexistente 404; estado no booleano 400', async () => {
    const r = await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { nombre: 'Diana 8', grupoId: 5 } });
    assert.strictEqual(r.status, 200);
    assert.strictEqual(r.body.data.grupo, 'Troquelado');
    assert.deepStrictEqual(db.auditoria.map((a) => a.campo), ['nombre', 'area']);
    assert.strictEqual((await llamar('PUT', '/INNPACK/maquinas/77', { cuerpo: { activo: false } })).status, 404);
    assert.strictEqual((await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { activo: 'no' } })).status, 400);
});

test('si falla la auditoría se revierte todo (atomicidad)', async () => {
    db.fallarAuditoria = true;
    const r = await llamar('PUT', '/INNPACK/maquinas/1', { cuerpo: { activo: false } });
    assert.strictEqual(r.status, 500);
    assert.strictEqual(db.maquinas[0].activo, true);
});

// ---- Aislamiento por empresa (la sesión solo administra su propia empresa) ----
test('sesión INNPACK no puede operar sobre FARET (403 en GET, POST, PUT y auditoría), ni siquiera ADMIN_TI', async () => {
    for (const [m, ruta, cuerpo] of [['GET', '/FARET/maquinas'], ['POST', '/FARET/maquinas', { nombre: 'X', grupoId: 'LAM' }],
        ['PUT', '/FARET/maquinas/1', { activo: false }], ['GET', '/FARET/auditoria'], ['GET', '/faret/inspectores']]) {
        const r = await llamar(m, ruta, { sub: 'I_ADMINTI', cuerpo });
        assert.strictEqual(r.status, 403, `${m} ${ruta}`);
        assert.strictEqual(r.body.ok, false);
    }
    assert.strictEqual(db.auditoria.length, 0);
});

test('sesión FARET no puede operar sobre INNPACK (403 en GET, POST, PUT y auditoría), ni siquiera ADMIN_TI', async () => {
    for (const [m, ruta, cuerpo] of [['GET', '/INNPACK/maquinas'], ['POST', '/INNPACK/maquinas', { nombre: 'Nueva', grupoId: 4 }],
        ['PUT', '/INNPACK/maquinas/1', { activo: false }], ['GET', '/INNPACK/auditoria'], ['PUT', '/INNPACK/inspectores/10', { activo: false }]]) {
        const r = await llamar(m, ruta, { sub: 'F_ADMINTI', cuerpo });
        assert.strictEqual(r.status, 403, `${m} ${ruta}`);
    }
    assert.strictEqual(db.maquinas.length, 1);
    assert.strictEqual(db.maquinas[0].activo, true);
    assert.strictEqual(db.usuarios[0].activo, true);
    assert.strictEqual(db.auditoria.length, 0);
});

test('sesiones legítimas siguen funcionando en su propia empresa', async () => {
    assert.strictEqual((await llamar('GET', '/INNPACK/maquinas', { sub: 'I_ADMINTI' })).status, 200);
    assert.strictEqual((await llamar('GET', '/INNPACK/auditoria', { sub: 'I_CALIDAD' })).status, 200);
    assert.strictEqual((await llamar('GET', '/FARET/maquinas', { sub: 'F_ADMINTI' })).status, 200);
    assert.strictEqual((await llamar('GET', '/FARET/auditoria', { sub: 'F_ADMINTI' })).status, 200);
});

// ---- Cuentas técnicas (columna oculto) ----
test('cuentas técnicas: no aparecen en el listado operativo, ni con incluirOcultos si no eres ADMIN_TI', async () => {
    let r = await llamar('GET', '/INNPACK/inspectores', { sub: 'I_ADMINTI' });
    assert.deepStrictEqual(r.body.data.map((u) => u.nombre), ['Ana Inspectora']);
    r = await llamar('GET', '/INNPACK/inspectores?incluirOcultos=1', { sub: 'I_CALIDAD' });
    assert.deepStrictEqual(r.body.data.map((u) => u.nombre), ['Ana Inspectora']);
});

test('cuentas técnicas: ADMIN_TI las ve solo con incluirOcultos=1 y marcadas como ocultas', async () => {
    const r = await llamar('GET', '/INNPACK/inspectores?incluirOcultos=1', { sub: 'I_ADMINTI' });
    assert.deepStrictEqual(r.body.data.map((u) => [u.nombre, u.oculto]), [['Ana Inspectora', false], ['Servicio Tecnico', true]]);
});

test('cuentas técnicas: no se pueden modificar (403 ADMIN_TI, 404 otros) y no se audita ni cambia nada', async () => {
    assert.strictEqual((await llamar('PUT', '/INNPACK/inspectores/11', { sub: 'I_ADMINTI', cuerpo: { activo: false } })).status, 403);
    assert.strictEqual((await llamar('PUT', '/INNPACK/inspectores/11', { sub: 'I_CALIDAD', cuerpo: { nombre: 'Otro' } })).status, 404);
    assert.strictEqual(db.usuarios[1].activo, true);
    assert.strictEqual(db.usuarios[1].nombre_completo, 'Servicio Tecnico');
    assert.strictEqual(db.auditoria.length, 0);
    // un inspector normal sigue editable
    assert.strictEqual((await llamar('PUT', '/INNPACK/inspectores/10', { cuerpo: { activo: false } })).status, 200);
});

test('cuentas técnicas: su nombre sigue contando para duplicados (no se puede crear otro igual)', async () => {
    const r = await llamar('POST', '/INNPACK/inspectores', { cuerpo: { nombre: 'SERVICIO TECNICO' } });
    assert.strictEqual(r.status, 409);
});
