// Administración de planta (QCC Desktop / Web): áreas, máquinas, operadores de máquina e inspectores de INNPACK y FARET.
// - Solo con sesión válida y rol permitido (middleware `autorizar('administrar', ..., { obligatorio: true })`).
// - Nunca se borra: se da de baja (activo/estado). Los registros históricos guardan el texto y no cambian.
// - Cada cambio (alta o campo modificado) queda en admin_planta_auditoria, en la misma transacción.
// - Aislamiento por empresa: la empresa de la URL debe coincidir con la de la sesión (req.auth.origen); sin excepciones, ni para ADMIN_TI.
// - Cuentas técnicas (columna `oculto`): no aparecen en los listados operativos y no se pueden modificar desde aquí; solo ADMIN_TI
//   puede verlas (?incluirOcultos=1) para auditarlas.
// - Los nombres de tabla/columna salen de ENTIDADES (lista fija); del cliente solo llegan valores, siempre parametrizados.
// - Defectos y controles de los formularios FARET (def_calidad, def_pt, chk_pallet): mismas reglas, más:
//   criticidad y orden; sin cambiar un texto ya usado en inspecciones; los defectos de Producto Terminado compartidos con INNPACK
//   (parametros_control_visual.empresa IS NULL) son de solo lectura desde FARET y los propios de FARET (empresa = 'FARET') nunca
//   los ve INNPACK (ver los filtros de catalogos/control/productoTerminado y la migración 015).
const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const { actor } = require('../utils/edicionInspecciones');

class ErrorAdmin extends Error {
    constructor(message, status = 400) { super(message); this.name = 'ErrorAdmin'; this.status = status; }
}

const bit = { col: 'activo', tipo: 'bit' };
const estado = { col: 'estado', tipo: 'estado' };

// pk: columna clave | grupo: relación con el área/proceso | codigo: columna visible solo lectura (tras crear)
const ENTIDADES = {
    INNPACK: {
        areas: { tabla: 'procesos', pk: 'id', nombre: 'nombre', max: 100, activo: bit },
        maquinas: {
            tabla: 'maquinas', pk: 'id', nombre: 'nombre', max: 120, activo: bit, codigo: 'codigo_qr',
            grupo: { col: 'proceso_id', tabla: 'procesos', pk: 'id', etiqueta: 'nombre' },
        },
        operadores: {
            tabla: 'operadores_maquina', pk: 'id', nombre: 'nombre', max: 150, activo: bit,
            grupo: { col: 'proceso_id', tabla: 'procesos', pk: 'id', etiqueta: 'nombre' },
        },
        inspectores: {
            tabla: 'usuarios', pk: 'id', nombre: 'nombre_completo', max: 150, activo: bit, codigo: 'codigo_usuario',
            filtro: `t.rol = N'operador'`, oculto: true,
        },
    },
    FARET: {
        areas: { tabla: 'calidad_faret_areas', pk: 'cod_area', nombre: 'nombre', max: 60, activo: estado, codigo: 'cod_area', mayusculas: true, orden: 'orden' },
        maquinas: {
            tabla: 'calidad_faret_maquinas', pk: 'id', nombre: 'nombre', max: 100, activo: estado, mayusculas: true,
            grupo: { col: 'cod_area', tabla: 'calidad_faret_areas', pk: 'cod_area', etiqueta: 'area_control' },
        },
        operadores: {
            tabla: 'calidad_faret_operadores_area', pk: 'id', nombre: 'nombre', max: 100, activo: estado, mayusculas: true,
            grupo: { col: 'cod_area', tabla: 'calidad_faret_areas', pk: 'cod_area', etiqueta: 'area_control' },
        },
        inspectores: { tabla: 'calidad_faret_operadores', pk: 'id', nombre: 'nombre', max: 150, activo: bit, mayusculas: true, oculto: true },
        // Calidad/Producción FARET: catálogo maestro de eventos (010). El ID, el orden por área y los campos *_origen los fija el alta.
        def_calidad: {
            tabla: 'calidad_faret_eventos', pk: 'id_evento', evento: true, nombre: 'defecto', max: 150, activo: estado, codigo: 'id_evento',
            grupo: { col: 'cod_area', tabla: 'calidad_faret_areas', pk: 'cod_area', etiqueta: 'area_control' },
            criticidad: ['Critico', 'Mayor', 'Menor'], ordenEditable: true, grupoInmutable: true,
        },
        // Producto Terminado: la tabla es compartida con INNPACK; FARET solo administra sus filas (empresa = 'FARET').
        def_pt: {
            tabla: 'parametros_control_visual', pk: 'id', nombre: 'nombre', max: 150, activo: bit,
            grupo: { col: 'proceso_id', tabla: 'procesos', pk: 'id', etiqueta: 'nombre', ids: [4, 5] },
            filtro: `t.proceso_id IN (4, 5) AND (t.empresa IS NULL OR t.empresa = N'FARET')`,
            criticidad: ['critico', 'mayor', 'menor'], compartidoSi: 't.empresa IS NULL', grupoInmutable: true,
            uso: 'dbo.registro_pt_hallazgo_defectos u WHERE u.defecto_id = t.id',
        },
        // Control Pallet/Papel: preguntas CUMPLE / NO CUMPLE.
        chk_pallet: {
            tabla: 'calidad_faret_pallet_preguntas', pk: 'id', nombre: 'texto', max: 255, activo: bit, ordenEditable: true,
            uso: 'dbo.registro_calidad_faret_pallet_respuestas u WHERE u.pregunta_id = t.id',
        },
    },
};

// Origen de la sesión (según el emisor del token) -> empresa que puede administrar.
const EMPRESA_DE_ORIGEN = { faret: 'FARET', innpack: 'INNPACK' };

const exigirEmpresaDeSesion = (req, empresa) => {
    if (EMPRESA_DE_ORIGEN[req.auth?.origen] !== empresa) throw new ErrorAdmin('Su sesión no puede administrar datos de otra empresa.', 403);
};

const esAdminTI = (req) => !!req.auth?.roles?.has('ADMIN_TI');

const resolver = (req) => {
    const empresa = String(req.params.empresa || '').toUpperCase();
    const cfg = ENTIDADES[empresa]?.[req.params.entidad];
    if (!cfg) throw new ErrorAdmin('Empresa o entidad no válida', 404);
    exigirEmpresaDeSesion(req, empresa);
    return { empresa, entidad: req.params.entidad, cfg };
};

// ---- Validación y utilidades ----------------------------------------------------------------------------------------
const limpiarNombre = (cfg, valor) => {
    let n = typeof valor === 'string' ? valor.replace(/\s+/g, ' ').trim() : '';
    if (!n) throw new ErrorAdmin('El nombre es obligatorio');
    if (cfg.mayusculas) n = n.toLocaleUpperCase('es');
    if (n.length > cfg.max) throw new ErrorAdmin(`El nombre no puede superar ${cfg.max} caracteres`);
    return n;
};

const esPkInt = (cfg) => cfg.pk === 'id';
const tipoPk = (cfg) => (esPkInt(cfg) ? sql.Int : sql.NVarChar(cfg.evento ? 10 : 3));
const valorPk = (cfg, v) => {
    if (esPkInt(cfg)) {
        const n = Number(v);
        if (!Number.isInteger(n) || n <= 0) throw new ErrorAdmin('Identificador inválido');
        return n;
    }
    const s = String(v || '').toUpperCase();
    if (cfg.evento) {
        if (!/^[A-Z]{3}-\d{3}$/.test(s)) throw new ErrorAdmin('Identificador inválido');
        return s;
    }
    if (!/^[A-Z]{3}$/.test(s)) throw new ErrorAdmin('Identificador inválido');
    return s;
};
const tipoGrupo = (cfg) => (cfg.grupo.pk === 'id' ? sql.Int : sql.NVarChar(3));

const aValorActivo = (cfg, activo) => (cfg.activo.tipo === 'bit' ? (activo ? 1 : 0) : (activo ? 'Activo' : 'Inactivo'));
const tipoActivo = (cfg) => (cfg.activo.tipo === 'bit' ? sql.Bit : sql.NVarChar(8));
const exprActivo = (cfg) => (cfg.activo.tipo === 'bit'
    ? `CAST(t.${cfg.activo.col} AS BIT)` : `CASE WHEN t.${cfg.activo.col} = N'Activo' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END`);

const limpiarCriticidad = (cfg, v) => {
    const c = cfg.criticidad.find((x) => x.toLowerCase() === String(v ?? '').trim().toLowerCase());
    if (!c) throw new ErrorAdmin('La criticidad es obligatoria: Crítico, Mayor o Menor');
    return c;
};
const limpiarOrden = (v) => {
    const n = Number(v);
    if (v === '' || v === null || typeof v === 'boolean' || !Number.isInteger(n) || n < 1 || n > 9999) throw new ErrorAdmin('El orden debe ser un número entero entre 1 y 9999');
    return n;
};
// El UPDATE de un evento dispara TR_calidad_faret_eventos_upd, que audita con SESSION_CONTEXT: se informa quién y por qué y se limpia
// siempre (la conexión vuelve al pool y el contexto es de la sesión, no de la transacción).
const conContextoDeAuditoria = async (tx, usuario, fn) => {
    const fijar = (u, m) => new sql.Request(tx).input('u', sql.NVarChar(128), u).input('m', sql.NVarChar(300), m)
        .query(`EXEC sp_set_session_context N'usuario', @u; EXEC sp_set_session_context N'motivo', @m;`);
    await fijar(usuario.nombre || usuario.id || 'desconocido', 'Administración de planta (QCC)');
    try { return await fn(); } finally { try { await fijar(null, null); } catch (_) { /* la transacción ya falló */ } }
};

const ascii = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9]+/g, '');

// ---- Consultas ------------------------------------------------------------------------------------------------------
// verOcultos: incluye las cuentas técnicas (solo para la edición protegida y para ADMIN_TI); por defecto se excluyen.
const selectFilas = (cfg, extraWhere = '', verOcultos = false) => {
    const cols = [`t.${cfg.pk} AS id`, `t.${cfg.nombre} AS nombre`, `${exprActivo(cfg)} AS activo`];
    if (cfg.oculto) cols.push('CAST(t.oculto AS BIT) AS oculto');
    let from = `dbo.${cfg.tabla} t`;
    if (cfg.codigo) cols.push(`t.${cfg.codigo} AS codigo`);
    if (cfg.criticidad) cols.push('t.criticidad AS criticidad');
    if (cfg.ordenEditable) cols.push('t.orden AS orden');
    if (cfg.evento) cols.push(`CAST(CASE WHEN t.requiere_aprobacion = 1 AND t.aprobacion <> N'APROBADA' THEN 1 ELSE 0 END AS BIT) AS pendienteAprobacion`);
    if (cfg.compartidoSi) cols.push(`CAST(CASE WHEN ${cfg.compartidoSi} THEN 1 ELSE 0 END AS BIT) AS compartido`);
    if (cfg.uso) cols.push(`CAST(CASE WHEN EXISTS (SELECT 1 FROM ${cfg.uso}) THEN 1 ELSE 0 END AS BIT) AS enUso`);
    if (cfg.grupo) {
        cols.push(`t.${cfg.grupo.col} AS grupoId`, `g.${cfg.grupo.etiqueta} AS grupo`);
        from += ` LEFT JOIN dbo.${cfg.grupo.tabla} g ON g.${cfg.grupo.pk} = t.${cfg.grupo.col}`;
    }
    const where = [cfg.filtro, cfg.oculto && !verOcultos ? 't.oculto = 0' : null, extraWhere].filter(Boolean).join(' AND ');
    const orden = [cfg.grupo ? 'g.' + cfg.grupo.etiqueta : cfg.orden ? 't.' + cfg.orden : null, cfg.ordenEditable ? 't.orden' : null, `t.${cfg.nombre}`].filter(Boolean).join(', ');
    return `SELECT ${cols.join(', ')} FROM ${from}${where ? ' WHERE ' + where : ''} ORDER BY ${orden}`;
};

const listar = async (req, res) => {
    try {
        const { cfg } = resolver(req);
        const verOcultos = req.query.incluirOcultos === '1' && esAdminTI(req);
        const pool = await getCalidadSqlServerPool();
        const r = await pool.request().query(selectFilas(cfg, '', verOcultos));
        res.json({ ok: true, data: r.recordset });
    } catch (error) {
        responderError(res, error, 'listar');
    }
};

const obtenerActual = async (tx, cfg, id) => {
    const r = await new sql.Request(tx).input('id', tipoPk(cfg), id).query(selectFilas(cfg, `t.${cfg.pk} = @id`, true));
    return r.recordset[0] || null;
};

const existeDuplicado = async (tx, cfg, nombre, grupoId, excluirId) => {
    const rq = new sql.Request(tx).input('nombre', sql.NVarChar(200), nombre);
    let where = `t.${cfg.nombre} COLLATE Latin1_General_CI_AI = @nombre COLLATE Latin1_General_CI_AI`;
    if (cfg.grupo) { rq.input('grupo', tipoGrupo(cfg), grupoId); where += ` AND t.${cfg.grupo.col} = @grupo`; }
    if (excluirId != null) { rq.input('excluir', tipoPk(cfg), excluirId); where += ` AND t.${cfg.pk} <> @excluir`; }
    if (cfg.filtro) where += ` AND ${cfg.filtro}`;
    const r = await rq.query(`SELECT TOP 1 1 AS x FROM dbo.${cfg.tabla} t WHERE ${where}`);
    return r.recordset.length > 0;
};

const validarGrupo = async (tx, cfg, grupoId) => {
    if (!cfg.grupo) return null;
    if (grupoId === undefined || grupoId === null || grupoId === '') throw new ErrorAdmin('El área/proceso es obligatorio');
    const valor = cfg.grupo.pk === 'id' ? Number(grupoId) : String(grupoId).toUpperCase();
    const r = await new sql.Request(tx).input('g', tipoGrupo(cfg), valor)
        .query(`SELECT TOP 1 1 AS x FROM dbo.${cfg.grupo.tabla} WHERE ${cfg.grupo.pk} = @g`);
    if (!r.recordset.length || (cfg.grupo.ids && !cfg.grupo.ids.includes(valor))) throw new ErrorAdmin('El área/proceso indicado no existe');
    return valor;
};

const auditar = async (tx, { empresa, entidad, clave, registro, accion, campo, anterior, nuevo, usuario }) => {
    await new sql.Request(tx)
        .input('empresa', sql.NVarChar(10), empresa)
        .input('entidad', sql.NVarChar(15), entidad)
        .input('clave', sql.NVarChar(20), String(clave))
        .input('registro', sql.NVarChar(150), registro)
        .input('accion', sql.NVarChar(10), accion)
        .input('campo', sql.NVarChar(30), campo)
        .input('anterior', sql.NVarChar(200), anterior == null ? null : String(anterior))
        .input('nuevo', sql.NVarChar(200), nuevo == null ? null : String(nuevo))
        .input('usuario', sql.NVarChar(150), usuario.nombre || usuario.id || 'desconocido')
        .input('origen', sql.NVarChar(10), usuario.origen)
        .query(`INSERT INTO dbo.admin_planta_auditoria (empresa, entidad, clave, registro, accion, campo, valor_anterior, valor_nuevo, usuario, origen)
                VALUES (@empresa, @entidad, @clave, @registro, @accion, @campo, @anterior, @nuevo, @usuario, @origen)`);
};

// ---- Alta -----------------------------------------------------------------------------------------------------------
// Columnas propias de cada entidad al crear (código QR de máquina, código de usuario, código/etiqueta de área FARET...).
const columnasExtra = async (tx, empresa, entidad, nombre, grupoId, body, cfg) => {
    const un = async (query, inputs = {}) => {
        const rq = new sql.Request(tx);
        for (const [k, [t, v]] of Object.entries(inputs)) rq.input(k, t, v);
        return (await rq.query(query)).recordset;
    };

    if (empresa === 'INNPACK' && entidad === 'maquinas') {
        let qr = typeof body.codigo === 'string' ? body.codigo.trim().toUpperCase() : '';
        if (!qr) {
            const [p] = await un('SELECT nombre FROM dbo.procesos WHERE id = @g', { g: [sql.Int, grupoId] });
            qr = `MAQ-${ascii(p.nombre).slice(0, 3)}-${ascii(nombre)}`;
        }
        if (qr.length > 100) throw new ErrorAdmin('El código QR no puede superar 100 caracteres');
        if ((await un('SELECT TOP 1 1 AS x FROM dbo.maquinas WHERE codigo_qr = @q', { q: [sql.NVarChar(100), qr] })).length)
            throw new ErrorAdmin('Ya existe una máquina con ese código QR', 409);
        return { codigo_qr: [sql.NVarChar(100), qr] };
    }

    if (empresa === 'INNPACK' && entidad === 'inspectores') {
        const palabras = nombre.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase()
            .split(' ').map((w) => w.replace(/[^A-Z]/g, '')).filter(Boolean);
        if (!palabras.length) throw new ErrorAdmin('El nombre no es válido para generar el código de usuario');
        const base = `CAL-${palabras[0][0]}${palabras[palabras.length - 1]}`.slice(0, 45);
        let codigo = base;
        for (let i = 2; (await un('SELECT TOP 1 1 AS x FROM dbo.usuarios WHERE codigo_usuario = @c', { c: [sql.NVarChar(50), codigo] })).length; i++) codigo = `${base}${i}`;
        return { codigo_usuario: [sql.NVarChar(50), codigo], rol: [sql.NVarChar(8), 'operador'] };
    }

    if (empresa === 'FARET' && cfg.evento) {
        // ID siguiente del área (nunca se reutiliza: los eventos no se borran). HOLDLOCK + UPDLOCK evitan que dos altas simultáneas elijan el mismo.
        const [m] = await un(
            `SELECT ISNULL(MAX(TRY_CAST(RIGHT(id_evento, 3) AS INT)), 0) + 1 AS n, ISNULL(MAX(orden), 0) + 1 AS o
             FROM dbo.calidad_faret_eventos WITH (UPDLOCK, HOLDLOCK) WHERE cod_area = @a`, { a: [sql.NVarChar(3), grupoId] });
        if (m.n > 999) throw new ErrorAdmin('El área alcanzó el máximo de 999 defectos');
        const criticidad = limpiarCriticidad(cfg, body.criticidad);
        const orden = body.orden === undefined || body.orden === '' ? m.o : limpiarOrden(body.orden);
        const etiqueta = { Critico: 'Crítico', Mayor: 'Mayor', Menor: 'Menor' }[criticidad];
        // Los campos *_origen son inmutables (trigger): para un defecto nuevo nacen iguales a los vigentes.
        return {
            id_evento: [sql.NVarChar(10), `${grupoId}-${String(m.n).padStart(3, '0')}`],
            tipo_registro: [sql.NVarChar(30), 'Desviación'],
            criticidad: [sql.NVarChar(10), criticidad], orden: [sql.SmallInt, orden],
            defecto_origen: [sql.NVarChar(150), nombre], criticidad_origen: [sql.NVarChar(10), criticidad],
            estado_origen: [sql.NVarChar(8), 'Activo'], texto_documento: [sql.NVarChar(300), `${etiqueta}: ${nombre}`],
        };
    }

    if (empresa === 'FARET' && entidad === 'def_pt') {
        return { criticidad: [sql.NVarChar(7), limpiarCriticidad(cfg, body.criticidad)], empresa: [sql.NVarChar(10), 'FARET'] };
    }

    if (empresa === 'FARET' && entidad === 'chk_pallet') {
        const [m] = await un('SELECT ISNULL(MAX(orden), 0) + 1 AS o FROM dbo.calidad_faret_pallet_preguntas');
        return { orden: [sql.Int, body.orden === undefined || body.orden === '' ? m.o : limpiarOrden(body.orden)] };
    }

    if (empresa === 'FARET' && entidad === 'areas') {
        const cod = String(body.codigo || '').toUpperCase();
        if (!/^[A-Z]{3}$/.test(cod)) throw new ErrorAdmin('El código del área debe tener 3 letras (ej. LAM)');
        if ((await un('SELECT TOP 1 1 AS x FROM dbo.calidad_faret_areas WHERE cod_area = @c', { c: [sql.NVarChar(3), cod] })).length)
            throw new ErrorAdmin('Ya existe un área con ese código', 409);
        const [m] = await un(`SELECT ISNULL(MAX(TRY_CAST(LEFT(area_control, 2) AS INT)), 0) + 1 AS n, ISNULL(MAX(orden), 0) + 1 AS o FROM dbo.calidad_faret_areas`);
        const areaControl = `${String(m.n).padStart(2, '0')}-${nombre}`;
        if (areaControl.length > 50) throw new ErrorAdmin('El nombre del área es demasiado largo');
        return { cod_area: [sql.NVarChar(3), cod], area_control: [sql.NVarChar(50), areaControl], orden: [sql.SmallInt, m.o] };
    }
    return {};
};

const crear = async (req, res) => {
    let tx = null;
    try {
        const { empresa, entidad, cfg } = resolver(req);
        const body = req.body && typeof req.body === 'object' ? req.body : {};
        const nombre = limpiarNombre(cfg, body.nombre);
        const usuario = actor(req);

        const pool = await getCalidadSqlServerPool();
        tx = new sql.Transaction(pool);
        await tx.begin();

        const grupoId = await validarGrupo(tx, cfg, body.grupoId);
        if (await existeDuplicado(tx, cfg, nombre, grupoId, null)) throw new ErrorAdmin('Ya existe un registro con ese nombre', 409);

        const extra = await columnasExtra(tx, empresa, entidad, nombre, grupoId, body, cfg);
        const columnas = { [cfg.nombre]: [sql.NVarChar(cfg.max), nombre], ...extra };
        if (cfg.grupo) columnas[cfg.grupo.col] = [tipoGrupo(cfg), grupoId];
        columnas[cfg.activo.col] = [tipoActivo(cfg), aValorActivo(cfg, true)];

        const rq = new sql.Request(tx);
        for (const [c, [t, v]] of Object.entries(columnas)) rq.input(c, t, v);
        const nombres = Object.keys(columnas);
        const ins = await rq.query(`INSERT INTO dbo.${cfg.tabla} (${nombres.join(', ')}) OUTPUT INSERTED.${cfg.pk} AS id VALUES (${nombres.map((c) => '@' + c).join(', ')})`);
        const id = ins.recordset[0].id;

        await auditar(tx, { empresa, entidad, clave: id, registro: nombre, accion: 'CREAR', campo: 'nombre', anterior: null, nuevo: nombre, usuario });
        const fila = await obtenerActual(tx, cfg, id);
        await tx.commit();
        res.status(201).json({ ok: true, data: fila });
    } catch (error) {
        if (tx) { try { await tx.rollback(); } catch (_) { /* ya cerrada */ } }
        responderError(res, error, 'crear');
    }
};

// ---- Modificación (nombre, área/proceso, baja/reactivación) ---------------------------------------------------------
const actualizar = async (req, res) => {
    let tx = null;
    try {
        const { empresa, entidad, cfg } = resolver(req);
        const id = valorPk(cfg, req.params.id);
        const body = req.body && typeof req.body === 'object' ? req.body : {};
        const usuario = actor(req);

        const pool = await getCalidadSqlServerPool();
        tx = new sql.Transaction(pool);
        await tx.begin();

        const actual = await obtenerActual(tx, cfg, id);
        if (!actual) throw new ErrorAdmin('Registro no encontrado', 404);
        // Cuenta técnica: protegida. Quien no es ADMIN_TI ni siquiera debe saber que existe.
        if (actual.oculto) throw esAdminTI(req) ? new ErrorAdmin('Cuenta técnica protegida: no se puede modificar desde Administración de planta.', 403) : new ErrorAdmin('Registro no encontrado', 404);

        // Defecto compartido con INNPACK: modificarlo cambiaría lo que ve INNPACK (no se hace desde FARET).
        if (actual.compartido) throw new ErrorAdmin('Este defecto es compartido con INNPACK y no se puede modificar desde FARET. Solo se administran los defectos propios de FARET.', 403);
        if (cfg.grupoInmutable && body.grupoId !== undefined && String(body.grupoId).toUpperCase() !== String(actual.grupoId)) {
            throw new ErrorAdmin('El área de un defecto no se puede cambiar: cree el defecto en la otra área y dé de baja este.');
        }
        if (cfg.evento && body.activo === true && !actual.activo && actual.pendienteAprobacion) {
            throw new ErrorAdmin('Este defecto está pendiente de aprobación de Calidad: no se puede activar desde este panel.', 409);
        }

        const sets = [];
        const cambios = [];
        const rq = new sql.Request(tx).input('id', tipoPk(cfg), id);

        let nombre = actual.nombre;
        if (body.nombre !== undefined) nombre = limpiarNombre(cfg, body.nombre);
        let grupoId = actual.grupoId;
        if (cfg.grupo && body.grupoId !== undefined) grupoId = await validarGrupo(tx, cfg, body.grupoId);

        if (nombre !== actual.nombre || (cfg.grupo && grupoId !== actual.grupoId)) {
            if (await existeDuplicado(tx, cfg, nombre, grupoId, id)) throw new ErrorAdmin('Ya existe un registro con ese nombre', 409);
        }
        if (nombre !== actual.nombre) {
            sets.push(`${cfg.nombre} = @nombre`); rq.input('nombre', sql.NVarChar(cfg.max), nombre);
            cambios.push({ campo: 'nombre', anterior: actual.nombre, nuevo: nombre });
        }
        let criticidad = actual.criticidad;
        if (cfg.criticidad && body.criticidad !== undefined) criticidad = limpiarCriticidad(cfg, body.criticidad);
        // Lo que ya respaldó una inspección (pregunta respondida, defecto marcado) conserva su texto y criticidad: el histórico se lee por id.
        if (cfg.uso && actual.enUso && (nombre !== actual.nombre || criticidad !== actual.criticidad)) {
            throw new ErrorAdmin('Ya se usó en inspecciones: su texto y criticidad no se modifican para no alterar el histórico. Dé de baja este y cree uno nuevo.', 409);
        }
        if (cfg.grupo && grupoId !== actual.grupoId) {
            sets.push(`${cfg.grupo.col} = @grupo`); rq.input('grupo', tipoGrupo(cfg), grupoId);
            cambios.push({ campo: 'area', anterior: actual.grupoId, nuevo: grupoId });
        }
        if (cfg.criticidad && criticidad !== actual.criticidad) {
            sets.push('criticidad = @criticidad'); rq.input('criticidad', sql.NVarChar(10), criticidad);
            cambios.push({ campo: 'criticidad', anterior: actual.criticidad, nuevo: criticidad });
        }
        if (cfg.ordenEditable && body.orden !== undefined) {
            const orden = limpiarOrden(body.orden);
            if (orden !== actual.orden) {
                sets.push('orden = @orden'); rq.input('orden', sql.Int, orden);
                cambios.push({ campo: 'orden', anterior: actual.orden, nuevo: orden });
            }
        }
        if (body.activo !== undefined) {
            if (typeof body.activo !== 'boolean') throw new ErrorAdmin('El estado debe ser verdadero o falso');
            if (body.activo !== !!actual.activo) {
                sets.push(`${cfg.activo.col} = @activo`); rq.input('activo', tipoActivo(cfg), aValorActivo(cfg, body.activo));
                cambios.push({ campo: 'activo', anterior: actual.activo ? 'Activo' : 'Baja', nuevo: body.activo ? 'Activo' : 'Baja' });
            }
        }

        if (sets.length) {
            const ejecutar = () => rq.query(`UPDATE dbo.${cfg.tabla} SET ${sets.join(', ')} WHERE ${cfg.pk} = @id`);
            if (cfg.evento) await conContextoDeAuditoria(tx, usuario, ejecutar); else await ejecutar();
            for (const c of cambios) await auditar(tx, { empresa, entidad, clave: id, registro: nombre, accion: 'MODIFICAR', ...c, usuario });
        }
        const fila = await obtenerActual(tx, cfg, id);
        await tx.commit();
        res.json({ ok: true, data: fila });
    } catch (error) {
        if (tx) { try { await tx.rollback(); } catch (_) { /* ya cerrada */ } }
        responderError(res, error, 'actualizar');
    }
};

const listarAuditoria = async (req, res) => {
    try {
        const empresa = String(req.params.empresa || '').toUpperCase();
        if (!ENTIDADES[empresa]) throw new ErrorAdmin('Empresa no válida', 404);
        exigirEmpresaDeSesion(req, empresa);
        const pool = await getCalidadSqlServerPool();
        const r = await pool.request().input('empresa', sql.NVarChar(10), empresa).query(`
            SELECT TOP 200 entidad, clave, registro, accion, campo, valor_anterior AS anterior, valor_nuevo AS nuevo, usuario, fecha
            FROM dbo.admin_planta_auditoria WHERE empresa = @empresa ORDER BY id DESC`);
        res.json({ ok: true, data: r.recordset });
    } catch (error) {
        responderError(res, error, 'auditoría');
    }
};

// Catálogo público de solo lectura para la app móvil FARET: áreas, máquinas y operadores activos (sin datos sensibles).
const catalogoPlantaFaret = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const areas = (await pool.request().query(
            `SELECT area_control AS areaControl, nombre FROM dbo.calidad_faret_areas WHERE estado = N'Activo' ORDER BY orden`)).recordset;
        const porArea = async (tabla) => {
            const r = await pool.request().query(`
                SELECT a.area_control AS areaControl, t.nombre FROM dbo.${tabla} t
                JOIN dbo.calidad_faret_areas a ON a.cod_area = t.cod_area
                WHERE t.estado = N'Activo' AND a.estado = N'Activo' ORDER BY t.nombre`);
            const mapa = {};
            for (const f of r.recordset) (mapa[f.areaControl] ||= []).push(f.nombre);
            return mapa;
        };
        res.json({ ok: true, data: {
            areas,
            maquinasPorArea: await porArea('calidad_faret_maquinas'),
            operadoresPorArea: await porArea('calidad_faret_operadores_area'),
        } });
    } catch (error) {
        console.error('Error al consultar el catálogo de planta Faret:', error.message);
        res.status(503).json({ ok: false, message: 'Catálogo de planta no disponible' });
    }
};

function responderError(res, error, contexto) {
    if (error instanceof ErrorAdmin) return res.status(error.status).json({ ok: false, message: error.message });
    if (error.number === 2627 || error.number === 2601) return res.status(409).json({ ok: false, message: 'Ya existe un registro con ese nombre' });
    console.error(`Error en administración de planta (${contexto}):`, error.message);
    return res.status(500).json({ ok: false, message: 'Error al procesar la solicitud' });
}

module.exports = { listar, crear, actualizar, listarAuditoria, catalogoPlantaFaret };
