// Arnés de integración de la clasificación de pallets contra SQL Server REAL (LocalDB, base aislada, compatibilidad 130 = SQL Server 2016).
// Ejecuta el CÓDIGO REAL del backend (control.controller + clasificacionPallets) sustituyendo solo el driver:
//   - escrituras: se registran como script T-SQL (misma sesión/transacción, EXEC sp_executesql con parámetros tipados) y se ejecutan con sqlcmd;
//   - lecturas: cada consulta se ejecuta en vivo con sqlcmd (FOR JSON) y el resultado vuelve al controlador.
//   - FPS se simula con tarjas de ejemplo (nunca se conecta a producción ni a FPS).
// Uso (lo invoca run_pallets_localdb.sh):  PIPE=... DB=... node pallets_localdb_harness.js <escenario>
//   escenario = completo | sin_migracion
const fs = require('fs');
const os = require('os');
const path = require('path');
const Module = require('module');
const { execFileSync } = require('child_process');

const BACKEND = path.join(__dirname, '..', '..');
const realSql = require(path.join(BACKEND, 'node_modules', 'mssql'));
const { PIPE, DB } = process.env;
const escenario = process.argv[2] || 'completo';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pallets-it-'));

const sqlcmd = (archivo) => execFileSync('sqlcmd', ['-S', PIPE, '-E', '-d', DB, '-y', '0', '-h', '-1', '-i', archivo], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });

// ---- tipos / literales ----
const decl = (t) => {
    const base = typeof t === 'function' ? t : t.type;
    if (base === realSql.NVarChar) return `nvarchar(${t.length || 'max'})`;
    if (base === realSql.Decimal) return `decimal(${t.precision},${t.scale})`;
    if (base === realSql.DateTime2) return 'datetime2(3)';
    if (base === realSql.Date) return 'date';
    if (base === realSql.Bit) return 'bit';
    return 'int';
};
const lit = (v) => {
    if (v === null || v === undefined) return 'NULL';
    if (typeof v === 'boolean') return v ? '1' : '0';
    if (typeof v === 'number') return String(v);
    if (v instanceof Date) return `'${v.toISOString().slice(0, 23)}'`;
    return `N'${String(v).replace(/'/g, "''")}'`;
};
const exec = (text, params, textoFinal = text) => {
    const defs = Object.entries(params).map(([n, p]) => `@${n} ${decl(p.t)}`).join(', ');
    const vals = Object.entries(params).map(([n, p]) => `@${n} = ${lit(p.v)}`).join(', ');
    return `EXEC sp_executesql N'${textoFinal.replace(/'/g, "''")}'${defs ? `, N'${defs}', ${vals}` : ''};`;
};

// ---- fase de escritura: se registra un script ----
const script = ['SET NOCOUNT ON;', 'SET QUOTED_IDENTIFIER ON;'];
let modo = 'escritura';
const ids = { registros_control: 0, pallet_clasificaciones: 0 };
if (escenario === 'completo' || escenario === 'sin_migracion') ids.registros_control = 0;

class Tx {
    async begin() { script.push('BEGIN TRANSACTION;'); }
    async commit() { script.push('COMMIT TRANSACTION;'); }
    async rollback() { script.push('IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;'); }
}

class Req {
    constructor() { this.params = {}; }
    input(n, t, v) { this.params[n] = { t, v }; return this; }
    async query(text) {
        if (modo === 'lectura') return this.leer(text);
        if (/^SAVE TRANSACTION|^ROLLBACK TRANSACTION/.test(text.trim())) { script.push(`${text.trim()};`); return { recordset: [] }; }
        if (/SELECT id FROM registros_control WHERE client_uuid/.test(text)) return { recordset: [] };
        if (/FROM parametros_control_visual\s+WHERE proceso_id/.test(text)) {
            // consulta de defectos válidos: se ejecuta de verdad en lectura (la base ya tiene el catálogo sembrado)
            return this.leer(text);
        }
        script.push(exec(text, this.params));
        const m = /INSERT INTO (registros_control|pallet_clasificaciones)\b/.exec(text);
        if (m) return { recordset: [{ id: ++ids[m[1]] }] };
        return { recordset: [] };
    }
    leer(text) {
        let t = text;
        const esEscritura = /^\s*(UPDATE|INSERT)\b/i.test(t);
        if (esEscritura) {
            t = `DECLARE @o TABLE (id INT); ${t.replace(/OUTPUT\s+INSERTED\.id/i, 'OUTPUT INSERTED.id INTO @o(id)')}; SELECT id FROM @o FOR JSON PATH`;
        } else {
            t = `${t.trim().replace(/;$/, '')} FOR JSON PATH`;
        }
        const f = path.join(tmp, `q${Date.now()}${Math.round(Math.random() * 1e6)}.sql`);
        fs.writeFileSync(f, `SET NOCOUNT ON;\nSET QUOTED_IDENTIFIER ON;\n${exec(text, this.params, t)}\n`, 'utf8');
        const salida = sqlcmd(f).split(/\r?\n/).filter((l) => l.trim() !== '').join('');
        if (/^Msg \d+/.test(salida)) throw new Error(salida);
        if (salida === '' || /^\(\d+ rows/.test(salida)) return { recordset: [] };
        return { recordset: JSON.parse(salida) };
    }
}

const FPS = {
    '466568-1': 'PLIEGO TROQUELADO', '466568-2': 'PLIEGO TROQUELADO', '466568-3': 'PLIEGO TROQUELADO',
};
class FpsReq {
    constructor() { this.p = {}; }
    input(n, t, v) { this.p[n] = v; return this; }
    async query(text) {
        if (/INNER JOIN WorkOrderRecords/.test(text)) {
            const nombre = FPS[this.p.codigo];
            return { recordset: nombre ? [{
                codigo: this.p.codigo, record_key: this.p.codigo.split('-')[0], n_etiqueta: Number(this.p.codigo.split('-')[1]), cantidad: this.p.codigo === '466568-2' ? 1200 : 0,
                total_etiquetas: 25, registro_activo: true, fecha_tarja: new Date('2026-11-22T21:08:49.730Z'), orden_fabricacion: 22669, np_faret: 22669, np_innpack: 3957,
                cliente: 'INNPACK SpA-A.G. SERVICIOS SPA', item_np: '1', codigo_producto: 'ST1102266931170', producto: nombre, proceso: 'TROQUEL',
                maquina: 'BOBST 142 - 2 (SFM)', operador: 'LUIS MONTOYA',
            }] : [] };
        }
        return { recordset: [] };
    }
}

const sqlStub = { ...realSql, Request: Req, Transaction: Tx };
const originalLoad = Module._load;
Module._load = function (request, ...rest) {
    if (request.endsWith('calidadSqlServerPool')) return { sql: sqlStub, getCalidadSqlServerPool: async () => ({ request: () => new Req() }) };
    if (request.endsWith('sqlServerPool')) return { sql: sqlStub, getSqlServerPool: async () => ({ request: () => new FpsReq() }) };
    return originalLoad.call(this, request, ...rest);
};

const control = require(path.join(BACKEND, 'src/controllers/control.controller'));
const pallets = require(path.join(BACKEND, 'src/controllers/clasificacionPallets.controller'));
const mkRes = () => { const r = { code: 200 }; r.status = (c) => { r.code = c; return r; }; r.json = (b) => { r.body = b; return r; }; return r; };
const silencio = () => { const l = console.log, w = console.warn, e = console.error; console.log = console.warn = console.error = () => {}; return () => { console.log = l; console.warn = w; console.error = e; }; };
const fallos = [];
const ok = (cond, msg) => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${msg}`); if (!cond) fallos.push(msg); };

const base = { usuarioId: 1, procesoId: 3, maquinaId: 6, turno: 'A', resultadoVisual: 'Cumple', fallasVisuales: [] };
const guardar = async (body) => { const r = mkRes(); const q = silencio(); await control.crearRegistroControl({ body }, r); q(); return r; };

(async () => {
    // Primer registro: ids reales empiezan en 1 (base nueva); el arnés los refleja.
    const r1 = await guardar({ ...base, pallets: [
        { codigo: '466568-1', color: 'AZUL', defectos: [1, 2], observacion: `Descalse en O'Brien "esquina" ñandú` },
        { codigo: '466568-2', color: 'ROJO', defectos: [3] },
        { codigo: '466568-3', color: 'VERDE' },
    ] });
    ok(r1.code === 201 && r1.body.data.pallets.guardados.length === 3, 'inspección con 3 pallets (AZUL/ROJO/VERDE) responde 201');
    const r2 = await guardar({ ...base, pallets: [{ codigo: '466568-1', color: 'VERDE', observacion: 'liberado tras revisión' }] });
    ok(r2.code === 201 && r2.body.data.pallets.guardados.length === 1, 'reclasificación AZUL -> VERDE responde 201');
    const r3 = await guardar({ ...base });
    ok(r3.code === 201 && !r3.body.data.pallets, 'inspección sin pallets responde 201 sin campo nuevo');
    const r4 = await guardar({ ...base, pallets: [{ codigo: '466568-999', color: 'AZUL' }, { codigo: 'XX', color: 'AZUL' }] });
    ok(r4.code === 201 && r4.body.data.pallets.guardados.length === 0 && r4.body.data.pallets.ignorados.length === 2, 'pallets inválidos no bloquean la inspección');

    fs.writeFileSync(path.join(tmp, 'escritura.sql'), `${script.join('\n')}\n`, 'utf8');
    const salidaEscritura = sqlcmd(path.join(tmp, 'escritura.sql'));
    const errores = salidaEscritura.split(/\r?\n/).filter((l) => /^Msg \d+/.test(l));

    if (escenario === 'sin_migracion') {
        // Las tablas de pallets NO existen (migración 015 pendiente): la inspección debe guardarse igual.
        ok(r1.body.data.pallets.guardados.length === 3, '(arnés) el controlador cree haber guardado; la verdad está en la base');
        console.log(`ERRORES_SQL=${errores.length}`);
        fs.writeFileSync(path.join(tmp, 'errores.txt'), errores.join('\n'));
        console.log(`TMP=${tmp}`);
        process.exit(0);
    }

    ok(errores.length === 0, `el script de escrituras corre sin errores SQL${errores.length ? ': ' + errores[0] : ''}`);

    // ---- lecturas en vivo ----
    modo = 'lectura';
    const q = silencio();
    const lista = mkRes(); await pallets.listarClasificaciones({ query: {} }, lista);
    const vig = mkRes(); await pallets.listarClasificaciones({ query: { vista: 'vigentes' } }, vig);
    const rojos = mkRes(); await pallets.listarClasificaciones({ query: { color: 'rojo', desde: '2020-01-01', hasta: '2030-01-01', procesoId: '3', maquinaId: '6', np: '3957', operador: 'montoya' } }, rojos);
    const porDefecto = mkRes(); await pallets.listarClasificaciones({ query: { defectoId: '1', limite: '10', pagina: '1' } }, porDefecto);
    const resumen = mkRes(); await pallets.resumenClasificaciones({ query: { vista: 'vigentes' } }, resumen);
    const resumenEv = mkRes(); await pallets.resumenClasificaciones({ query: {} }, resumenEv);
    const defectos = mkRes(); await pallets.defectosPorClasificacion({ query: {} }, defectos);
    const historial = mkRes(); await pallets.obtenerHistorial({ params: { codigo: '466568-1' } }, historial);
    const detalle = mkRes(); await pallets.obtenerClasificacion({ params: { id: '1' } }, detalle);
    const tarja = mkRes(); await pallets.obtenerTarja({ params: { codigo: '466568-1' } }, tarja);
    q();

    ok(lista.code === 200 && lista.body.data.total === 4, `listado (eventos): 4 clasificaciones (total=${lista.body.data.total})`);
    ok(vig.body.data.total === 3, `listado vista=vigentes: 3 pallets vigentes (total=${vig.body.data.total})`);
    const vigente1 = vig.body.data.items.find((i) => i.palletCodigo === '466568-1');
    ok(vigente1 && vigente1.color === 'VERDE' && vigente1.vigente === true, 'el pallet 466568-1 reclasificado figura VERDE como vigente');
    ok(rojos.body.data.total === 1 && rojos.body.data.items[0].palletCodigo === '466568-2', 'filtros combinados (color/fechas/proceso/máquina/NP/operador) devuelven el ROJO');
    ok(rojos.body.data.items[0].fps.cliente === 'INNPACK SpA-A.G. SERVICIOS SPA' && rojos.body.data.items[0].fps.cantidadUnidades === 1200, 'se conserva la copia de datos de FPS (cliente, cantidad)');
    ok(rojos.body.data.items[0].defectos.length === 1, 'el listado incluye los defectos de la clasificación');
    ok(porDefecto.body.data.total === 1, 'filtro por defecto');
    const t = resumen.body.data.totales;
    ok(t.azul === 0 && t.rojo === 1 && t.verde === 2 && t.total === 3, `resumen vigentes: azul 0 / rojo 1 / verde 2 (${JSON.stringify(t)})`);
    const te = resumenEv.body.data.totales;
    ok(te.azul === 1 && te.rojo === 1 && te.verde === 2 && te.total === 4, `resumen eventos: azul 1 / rojo 1 / verde 2 (${JSON.stringify(te)})`);
    ok(resumenEv.body.data.porProceso.length === 1 && resumenEv.body.data.porDia.length >= 1, 'resumen por proceso/máquina/día');
    ok(defectos.body.data.porDefecto.length === 3 && defectos.body.data.sinDefecto.length >= 1, 'defectos por clasificación (color x defecto)');
    ok(historial.body.data.length === 2 && historial.body.data[0].color === 'AZUL' && historial.body.data[1].color === 'VERDE', 'historial del pallet conserva AZUL y luego VERDE');
    ok(detalle.body.data.id === 1 && detalle.body.data.observacion.includes("O'Brien") && detalle.body.data.observacion.includes('ñandú'), 'detalle con observación (comillas y ñ) íntegra');
    ok(tarja.body.data.estadoActual && tarja.body.data.estadoActual.color === 'VERDE', 'la tarja muestra el estado vigente VERDE al reescanear');

    // ---- anulación lógica ----
    const sinMotivo = mkRes(); await pallets.anularClasificacion({ params: { id: '2' }, body: {} }, sinMotivo);
    ok(sinMotivo.code === 400, 'anular sin motivo se rechaza');
    const an = mkRes(); const q2 = silencio(); await pallets.anularClasificacion({ params: { id: '2' }, body: { motivo: 'Pallet equivocado' }, auth: { nombre: 'Calidad Uno' } }, an); q2();
    ok(an.code === 200, 'anular con motivo responde 200');
    const an2 = mkRes(); const q3 = silencio(); await pallets.anularClasificacion({ params: { id: '2' }, body: { motivo: 'otra vez' } }, an2); q3();
    ok(an2.code === 404, 'anular dos veces se rechaza');
    const lista2 = mkRes(); const q4 = silencio(); await pallets.listarClasificaciones({ query: {} }, lista2); q4();
    ok(lista2.body.data.total === 3, 'el listado por defecto oculta las anuladas');
    const lista3 = mkRes(); const q5 = silencio(); await pallets.listarClasificaciones({ query: { incluirAnuladas: '1' } }, lista3); q5();
    ok(lista3.body.data.total === 4 && lista3.body.data.items.find((i) => i.id === 2).anulado === true, 'incluirAnuladas=1 las muestra marcadas (nunca se borran)');

    console.log(fallos.length === 0 ? 'HARNESS_OK' : `HARNESS_FALLOS=${fallos.length}`);
    process.exit(fallos.length === 0 ? 0 : 1);
})().catch((e) => { console.error('HARNESS_ERROR', e); process.exit(2); });
