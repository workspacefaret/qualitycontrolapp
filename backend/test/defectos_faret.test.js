// Defectos y controles FARET: tolerancia del checklist Pallet/Papel ante cambios en curso y aislamiento por empresa de
// parametros_control_visual (guarda de código: ningún consumidor que enumere defectos puede olvidar el filtro de empresa).
// Ejecutar: npm test
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const Module = require('module');

const cargar = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: new Proxy({}, { get: () => () => 'T' }), getCalidadSqlServerPool: async () => ({}) };
    return cargar.call(this, request, ...rest);
};
const { validarChecklist } = require('../src/controllers/calidadFaretPallet.controller');

const P = (id, activo, minutos) => ({ id, activo, minutos });
const T = 240;

test('checklist completo y vigente: válido', () => {
    assert.strictEqual(validarChecklist([P(1, true, 9999), P(2, true, 9999)], new Set([1, 2]), null, T), null);
});
test('falta una pregunta vigente antigua: se rechaza', () => {
    assert.match(validarChecklist([P(1, true, 9999), P(2, true, 9999)], new Set([1]), null, T), /todas las preguntas vigentes/);
});
test('app anterior (sin lista de mostradas): una pregunta reciente tampoco puede faltar', () => {
    assert.notStrictEqual(validarChecklist([P(1, true, 9999), P(2, true, 10)], new Set([1]), null, T), null);
});
test('pregunta nueva ya vieja (pasó la tolerancia): vuelve a ser obligatoria', () => {
    assert.notStrictEqual(validarChecklist([P(1, true, 9999), P(2, true, 300)], new Set([1]), null, T), null);
});
test('pregunta dada de baja mientras se llenaba: se acepta su respuesta', () => {
    assert.strictEqual(validarChecklist([P(1, true, 9999), P(2, false, 9999)], new Set([1, 2]), null, T), null);
});
test('pregunta inactiva no es obligatoria', () => {
    assert.strictEqual(validarChecklist([P(1, true, 9999), P(2, false, 9999)], new Set([1]), null, T), null);
});
test('pregunta inexistente: se rechaza', () => {
    assert.match(validarChecklist([P(1, true, 9999)], new Set([1, 77]), null, T), /no existen/);
});

const S = (...ids) => new Set(ids);
test('con preguntasMostradas: lo que la app mostró es obligatorio aunque sea reciente', () => {
    assert.notStrictEqual(validarChecklist([P(1, true, 9999), P(2, true, 10)], S(1), S(1, 2), T), null);
});
test('con preguntasMostradas: una vigente no mostrada y reciente se tolera', () => {
    assert.strictEqual(validarChecklist([P(1, true, 9999), P(2, true, 10)], S(1), S(1), T), null);
});
test('con preguntasMostradas: una vigente ANTIGUA no mostrada se rechaza (no se puede omitir un control)', () => {
    assert.notStrictEqual(validarChecklist([P(1, true, 9999), P(2, true, 9999)], S(1), S(1), T), null);
});
test('con preguntasMostradas inexistentes se rechaza', () => {
    assert.match(validarChecklist([P(1, true, 9999)], S(1), S(1, 55), T), /no existen/);
});
test('sin preguntasMostradas (app anterior): exigencia estricta aunque la pregunta sea reciente', () => {
    assert.notStrictEqual(validarChecklist([P(1, true, 9999), P(2, true, 10)], S(1), null, T), null);
});

// ---- Guarda: toda consulta del backend que lista parametros_control_visual debe filtrar por empresa ----
const SRC = path.join(__dirname, '..', 'src');
const archivos = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? archivos(path.join(d, e.name)) : e.name.endsWith('.js') ? [path.join(d, e.name)] : []));
test('guarda: cada FROM parametros_control_visual del backend filtra por empresa o es una resolución por id/administración', () => {
    const permitidos = new Set(['adminPlanta.controller.js']); // administra con su propio filtro (def_pt)
    const sinFiltro = [];
    for (const f of archivos(SRC)) {
        if (permitidos.has(path.basename(f))) continue;
        const s = fs.readFileSync(f, 'utf8');
        const re = /FROM\s+parametros_control_visual\b/gi;
        let m;
        while ((m = re.exec(s))) {
            const ventana = s.slice(m.index, m.index + 420);
            const hastaFin = ventana.split(/ORDER BY|`\s*\)|`;/)[0];
            if (!/empresa/i.test(hastaFin) && !/\bWHERE\s+[a-z.]*id\s*(=|IN)/i.test(hastaFin)) sinFiltro.push(`${path.relative(SRC, f)}:${s.slice(0, m.index).split('\n').length}`);
        }
    }
    assert.deepStrictEqual(sinFiltro, [], 'consultas sin filtro de empresa: ' + sinFiltro.join(', '));
});
