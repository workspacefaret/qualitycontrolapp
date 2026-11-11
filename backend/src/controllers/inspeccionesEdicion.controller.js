// Edición de inspecciones FARET (Calidad y Pallet/Papel) para corregir errores de captura.
// - Solo ADMIN, ADMIN_TI e INSPECTOR (middleware `autorizar('editar', ..., { obligatorio: true })`, nunca off/observar).
// - Motivo del cambio obligatorio; cada campo modificado queda en inspecciones_faret_auditoria (usuario, fecha, anterior, nuevo, motivo).
// - No se editan fecha/hora de captura, operador que registró, client_uuid ni adjuntos. El histórico (sin id_evento/criticidad) se conserva.
// - Misma transacción para registro + defectos/respuestas + auditoría: o se guarda todo o nada.
const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const { ErrorValidacion, resolverDefectos, esErrorTriggerEvento } = require('../utils/eventosCalidadFaret');
const {
    ErrorEdicion, validarMotivo, norm, textoOpcional, textoObligatorio, actor, registrarAuditoria, listarAuditoria,
} = require('../utils/edicionInspecciones');

const MAX = sql.MAX;
const TIPOS_MATERIAL = ['NV', 'PAPEL'];
const RESULTADOS = ['CUMPLE', 'NO_CUMPLE'];

// ---------------------------------------------------------------------------------------------------------------------
// Calidad
// ---------------------------------------------------------------------------------------------------------------------
// [clave del cuerpo, columna, largo máximo (MAX = ilimitado), etiqueta, obligatorio]
const CAMPOS_CALIDAD = [
    ['nvFaret', 'nv_faret', 100, 'NV Faret', true],
    ['nPliego', 'n_pliego', 100, 'N° de pliego', false],
    ['nPasada', 'n_pasada', 100, 'N° de pasada', false],
    ['nItem', 'n_item', 100, 'N° de ítem', false],
    ['pliegoControlN', 'pliego_control_n', 100, 'Pliego control N°', false],
    ['observaciones', 'observaciones', MAX, 'Observaciones', false],
    ['areaControl', 'area_control', 50, 'Área de control', true],
    ['operador', 'operador', 150, 'Operador', true],
    ['operadorOtro', 'operador_otro', 150, 'Operador (otro)', false],
    ['maquina', 'maquina', 100, 'Máquina', true],
    ['areaDefecto', 'area_defecto', 50, 'Área del defecto', false],
    ['tipoFolia', 'tipo_folia', 150, 'Tipo de folia', false],
    ['accionCorrectiva', 'accion_correctiva', MAX, 'Acción correctiva', false],
];
const CAMPOS_CALIDAD_DEFECTO = new Set(['areaDefecto', 'tipoFolia', 'accionCorrectiva']);   // se vacían si no presenta defectos

const largoSql = (max) => (max === MAX ? MAX : max);
const largoTexto = (max) => (max === MAX ? 1000000 : max);

const textoDefecto = (d) => `${d.id_evento ? `${d.id_evento} · ` : ''}${d.defecto}${d.criticidad ? ` (${d.criticidad})` : ''}`;
const listaDefectos = (arr) => (arr.length ? arr.map(textoDefecto).sort().join('; ') : null);

const responderError = (res, error, contexto) => {
    if (error instanceof ErrorEdicion || error instanceof ErrorValidacion) {
        return res.status(error.status).json({ ok: false, message: error.message });
    }
    if (esErrorTriggerEvento(error)) {
        return res.status(400).json({ ok: false, message: 'El evento de calidad ya no está disponible o no corresponde al área; actualice el catálogo' });
    }
    console.error(`Error al editar ${contexto}:`, error.message);
    return res.status(500).json({ ok: false, message: 'Error al guardar los cambios' });
};

const idValido = (v) => {
    const n = Number(v);
    if (!Number.isInteger(n) || n <= 0) throw new ErrorEdicion('Identificador de registro inválido');
    return n;
};

const actualizarRegistroCalidadFaret = async (req, res) => {
    let transaction = null;
    try {
        const id = idValido(req.params.id);
        const body = req.body && typeof req.body === 'object' ? req.body : {};
        const motivo = validarMotivo(body.motivo);
        const usuario = actor(req);

        // ---- Validación de lo recibido (undefined = no se envió = no se modifica) ----
        const nuevo = {};
        for (const [clave, , max, etiqueta, oblig] of CAMPOS_CALIDAD) {
            const v = oblig ? textoObligatorio(body[clave], largoTexto(max), etiqueta) : textoOpcional(body[clave], largoTexto(max), etiqueta);
            if (v !== undefined) nuevo[clave] = v;
        }
        for (const clave of ['nvVoBoAprobado', 'presentaDefectos']) {
            if (body[clave] !== undefined) {
                if (typeof body[clave] !== 'boolean') throw new ErrorEdicion(`${clave} debe ser verdadero o falso`);
                nuevo[clave] = body[clave];
            }
        }
        if (body.defectos !== undefined && !Array.isArray(body.defectos)) throw new ErrorEdicion('defectos debe ser una lista');

        const pool = await getCalidadSqlServerPool();
        transaction = new sql.Transaction(pool);
        await transaction.begin();

        const actualRs = await new sql.Request(transaction).input('id', sql.Int, id).query(
            `SELECT nv_faret, nv_vb_aprobado, n_pliego, n_pasada, n_item, pliego_control_n, observaciones, area_control, operador,
                    operador_otro, maquina, presenta_defectos, area_defecto, tipo_folia, accion_correctiva
             FROM registros_calidad_faret WITH (UPDLOCK, ROWLOCK) WHERE id = @id AND eliminado = 0`);
        if (actualRs.recordset.length === 0) {
            const e = new ErrorEdicion('Registro no encontrado', 404);
            throw e;
        }
        const a = actualRs.recordset[0];
        const actual = {
            nvVoBoAprobado: !!a.nv_vb_aprobado, presentaDefectos: !!a.presenta_defectos,
        };
        for (const [clave, col] of CAMPOS_CALIDAD) actual[clave] = a[col] === undefined ? null : a[col];

        const final = { ...actual, ...nuevo };
        if (!final.presentaDefectos) {
            for (const c of CAMPOS_CALIDAD_DEFECTO) final[c] = null;
        }
        // Obligatorios que siguen siendo obligatorios aunque no se hayan enviado (no pueden quedar vacíos).
        for (const [clave, , , etiqueta, oblig] of CAMPOS_CALIDAD) {
            if (oblig && !norm(final[clave])) throw new ErrorEdicion(`${etiqueta} es obligatorio`);
        }

        // ---- Defectos ----
        const defRs = await new sql.Request(transaction).input('id', sql.Int, id).query(
            'SELECT defecto, id_evento, criticidad FROM registro_calidad_faret_defectos WHERE registro_id = @id');
        const defActuales = defRs.recordset;
        const areaCambia = norm(final.areaDefecto) !== norm(actual.areaDefecto);

        let quitar = [];
        let agregar = [];
        let defectosCambian = false;
        if (!final.presentaDefectos) {
            quitar = defActuales;
        } else if (body.defectos !== undefined) {
            const retenidos = new Set();
            const aResolver = [];
            for (const d of body.defectos) {
                if (typeof d === 'string') {
                    const t = d.trim();
                    const fila = defActuales.find((x) => !x.id_evento && x.defecto === t);
                    if (fila) retenidos.add(fila); else aResolver.push(d);
                } else if (d && typeof d === 'object' && !Array.isArray(d) && typeof d.idEvento === 'string') {
                    const idEv = d.idEvento.trim().toUpperCase();
                    const fila = defActuales.find((x) => x.id_evento === idEv);
                    if (fila) retenidos.add(fila); else aResolver.push(d);
                } else {
                    aResolver.push(d);   // formato inválido: resolverDefectos lo rechaza con su mensaje
                }
            }
            if (areaCambia && [...retenidos].some((x) => x.id_evento)) {
                throw new ErrorEdicion('Al cambiar el área del defecto debe volver a seleccionar los defectos del catálogo');
            }
            const resueltos = aResolver.length ? await resolverDefectos(pool, aResolver, final.areaDefecto) : [];
            quitar = defActuales.filter((x) => !retenidos.has(x));
            agregar = resueltos;
            defectosCambian = true;
        } else if (areaCambia && defActuales.some((x) => x.id_evento)) {
            throw new ErrorEdicion('Al cambiar el área del defecto debe volver a seleccionar los defectos del catálogo');
        }
        if (quitar.length || agregar.length) defectosCambian = true; else defectosCambian = false;

        // ---- Cambios (para auditar y para detectar "sin cambios") ----
        const cambios = [];
        for (const [clave, , , etiqueta] of CAMPOS_CALIDAD) {
            if (norm(final[clave]) !== norm(actual[clave])) cambios.push({ campo: etiqueta, anterior: norm(actual[clave]), nuevo: norm(final[clave]) });
        }
        if (final.nvVoBoAprobado !== actual.nvVoBoAprobado) {
            cambios.push({ campo: 'NV VoBo aprobado', anterior: norm(actual.nvVoBoAprobado), nuevo: norm(final.nvVoBoAprobado) });
        }
        if (final.presentaDefectos !== actual.presentaDefectos) {
            cambios.push({ campo: '¿Presenta defectos?', anterior: norm(actual.presentaDefectos), nuevo: norm(final.presentaDefectos) });
        }
        if (defectosCambian) {
            const finales = [
                ...defActuales.filter((x) => !quitar.includes(x)),
                ...agregar.map((x) => ({ defecto: x.texto, id_evento: x.idEvento, criticidad: x.criticidad })),
            ];
            cambios.push({ campo: 'Defectos', anterior: listaDefectos(defActuales), nuevo: listaDefectos(finales) });
        }
        if (cambios.length === 0) throw new ErrorEdicion('No hay cambios que guardar');

        // ---- Escritura ----
        const rq = new sql.Request(transaction).input('id', sql.Int, id)
            .input('nvVoBoAprobado', sql.Bit, final.nvVoBoAprobado ? 1 : 0)
            .input('presentaDefectos', sql.Bit, final.presentaDefectos ? 1 : 0);
        for (const [clave, , max] of CAMPOS_CALIDAD) rq.input(clave, sql.NVarChar(largoSql(max)), norm(final[clave]));
        await rq.query(
            `UPDATE registros_calidad_faret SET
               nv_faret = @nvFaret, nv_vb_aprobado = @nvVoBoAprobado, n_pliego = @nPliego, n_pasada = @nPasada, n_item = @nItem,
               pliego_control_n = @pliegoControlN, observaciones = @observaciones, area_control = @areaControl, operador = @operador,
               operador_otro = @operadorOtro, maquina = @maquina, presenta_defectos = @presentaDefectos, area_defecto = @areaDefecto,
               tipo_folia = @tipoFolia, accion_correctiva = @accionCorrectiva
             WHERE id = @id AND eliminado = 0`);

        for (const q of quitar) {
            await new sql.Request(transaction)
                .input('id', sql.Int, id).input('defecto', sql.NVarChar(150), q.defecto).input('idEvento', sql.NVarChar(10), q.id_evento || null)
                .query(`DELETE FROM registro_calidad_faret_defectos
                        WHERE registro_id = @id AND defecto = @defecto AND ((@idEvento IS NULL AND id_evento IS NULL) OR id_evento = @idEvento)`);
        }
        for (const d of agregar) {
            const r = new sql.Request(transaction).input('registroId', sql.Int, id).input('defecto', sql.NVarChar(150), d.texto);
            if (d.idEvento) {
                await r.input('idEvento', sql.NVarChar(10), d.idEvento).input('criticidad', sql.NVarChar(10), d.criticidad)
                    .query('INSERT INTO registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) VALUES (@registroId, @defecto, @idEvento, @criticidad)');
            } else {
                await r.query('INSERT INTO registro_calidad_faret_defectos (registro_id, defecto) VALUES (@registroId, @defecto)');
            }
        }

        await registrarAuditoria(transaction, { tipo: 'CALIDAD', registroId: id, cambios, motivo, usuario });
        await transaction.commit();
        res.json({ ok: true, message: 'Registro actualizado correctamente', data: { registroId: id, camposModificados: cambios.length } });
    } catch (error) {
        if (transaction) { try { await transaction.rollback(); } catch (_) { /* ya cerrada */ } }
        responderError(res, error, 'registro calidad Faret');
    }
};

// ---------------------------------------------------------------------------------------------------------------------
// Pallet / Papel
// ---------------------------------------------------------------------------------------------------------------------
const CAMPOS_PALLET = [
    ['dimension', 'dimension', 100, 'Dimensión', true],
    ['fibra', 'fibra', 50, 'Fibra', false],
    ['numeroPallet', 'numero_pallet', 100, 'N° de pallet', true],
    ['observaciones', 'observaciones', MAX, 'Observaciones', false],
    ['areaControl', 'area_control', 100, 'Área de control', false],
    ['operador', 'operador', 150, 'Operador', false],
    ['operadorOtro', 'operador_otro', 150, 'Operador (otro)', false],
    ['maquina', 'maquina', 150, 'Máquina', false],
];

const textoRespuesta = (r) => (r.resultado === 'NO_CUMPLE' ? `NO CUMPLE — ${r.observacion || ''}`.trim() : 'CUMPLE');

const actualizarRegistroCalidadFaretPallet = async (req, res) => {
    let transaction = null;
    try {
        const id = idValido(req.params.id);
        const body = req.body && typeof req.body === 'object' ? req.body : {};
        const motivo = validarMotivo(body.motivo);
        const usuario = actor(req);

        const nuevo = {};
        for (const [clave, , max, etiqueta, oblig] of CAMPOS_PALLET) {
            const v = oblig ? textoObligatorio(body[clave], largoTexto(max), etiqueta) : textoOpcional(body[clave], largoTexto(max), etiqueta);
            if (v !== undefined) nuevo[clave] = v;
        }
        if (body.tipoMaterial !== undefined) {
            if (!TIPOS_MATERIAL.includes(body.tipoMaterial)) throw new ErrorEdicion('Tipo de material inválido. Debe ser NV o PAPEL');
            nuevo.tipoMaterial = body.tipoMaterial;
        }
        if (body.numeroPasadasPrensa !== undefined) {
            if (body.numeroPasadasPrensa === null || body.numeroPasadasPrensa === '') nuevo.numeroPasadasPrensa = null;
            else if ([1, 2, 3].includes(Number(body.numeroPasadasPrensa))) nuevo.numeroPasadasPrensa = Number(body.numeroPasadasPrensa);
            else throw new ErrorEdicion('El número de pasadas de prensa debe ser 1, 2 o 3');
        }
        let respuestasNuevas = null;
        if (body.respuestas !== undefined) {
            if (!Array.isArray(body.respuestas) || body.respuestas.length === 0) throw new ErrorEdicion('El checklist de respuestas es inválido');
            respuestasNuevas = new Map();
            for (const r of body.respuestas) {
                const pid = Number(r?.preguntaId);
                if (!Number.isInteger(pid)) throw new ErrorEdicion('Hay respuestas con preguntaId inválido');
                if (respuestasNuevas.has(pid)) throw new ErrorEdicion('El checklist tiene preguntas duplicadas');
                if (!RESULTADOS.includes(r.resultado)) throw new ErrorEdicion(`Resultado inválido para preguntaId ${pid}`);
                const obs = textoOpcional(r.observacion === undefined ? null : r.observacion, largoTexto(MAX), 'Observación');
                if (r.resultado === 'NO_CUMPLE' && !obs) throw new ErrorEdicion(`Falta observación obligatoria para la respuesta NO_CUMPLE de preguntaId ${pid}`);
                respuestasNuevas.set(pid, { resultado: r.resultado, observacion: obs });
            }
        }

        const pool = await getCalidadSqlServerPool();
        transaction = new sql.Transaction(pool);
        await transaction.begin();

        const actualRs = await new sql.Request(transaction).input('id', sql.Int, id).query(
            `SELECT tipo_material, dimension, fibra, numero_pallet, numero_pasadas_prensa, observaciones, area_control, operador,
                    operador_otro, maquina
             FROM registros_calidad_faret_pallet WITH (UPDLOCK, ROWLOCK) WHERE id = @id AND eliminado = 0`);
        if (actualRs.recordset.length === 0) throw new ErrorEdicion('Registro no encontrado', 404);
        const a = actualRs.recordset[0];
        const actual = { tipoMaterial: a.tipo_material, numeroPasadasPrensa: a.numero_pasadas_prensa ?? null };
        for (const [clave, col] of CAMPOS_PALLET) actual[clave] = a[col] === undefined ? null : a[col];
        const final = { ...actual, ...nuevo };
        for (const [clave, , , etiqueta, oblig] of CAMPOS_PALLET) {
            if (oblig && !norm(final[clave])) throw new ErrorEdicion(`${etiqueta} es obligatorio`);
        }

        const respRs = await new sql.Request(transaction).input('id', sql.Int, id).query(
            `SELECT resp.pregunta_id AS preguntaId, p.texto, resp.resultado, resp.observacion
             FROM registro_calidad_faret_pallet_respuestas resp
             INNER JOIN calidad_faret_pallet_preguntas p ON p.id = resp.pregunta_id
             WHERE resp.registro_id = @id`);
        const respActuales = new Map(respRs.recordset.map((r) => [r.preguntaId, r]));
        if (respuestasNuevas) {
            // Solo las preguntas que ya tiene el registro (no se agregan ni se quitan preguntas al editar).
            const mismas = respuestasNuevas.size === respActuales.size && [...respActuales.keys()].every((k) => respuestasNuevas.has(k));
            if (!mismas) throw new ErrorEdicion('El checklist debe responder exactamente las preguntas del registro');
        }

        const cambios = [];
        for (const [clave, , , etiqueta] of CAMPOS_PALLET) {
            if (norm(final[clave]) !== norm(actual[clave])) cambios.push({ campo: etiqueta, anterior: norm(actual[clave]), nuevo: norm(final[clave]) });
        }
        if (final.tipoMaterial !== actual.tipoMaterial) cambios.push({ campo: 'Tipo de material', anterior: actual.tipoMaterial, nuevo: final.tipoMaterial });
        if (norm(final.numeroPasadasPrensa) !== norm(actual.numeroPasadasPrensa)) {
            cambios.push({ campo: 'Pasadas de prensa', anterior: norm(actual.numeroPasadasPrensa), nuevo: norm(final.numeroPasadasPrensa) });
        }
        const respCambiadas = [];
        if (respuestasNuevas) {
            for (const [pid, n] of respuestasNuevas) {
                const act = respActuales.get(pid);
                const antes = textoRespuesta(act);
                const despues = textoRespuesta(n);
                if (antes !== despues) {
                    respCambiadas.push({ pid, n });
                    cambios.push({ campo: `Checklist: ${act.texto}`.slice(0, 200), anterior: antes, nuevo: despues });
                }
            }
        }
        if (cambios.length === 0) throw new ErrorEdicion('No hay cambios que guardar');

        const rq = new sql.Request(transaction).input('id', sql.Int, id)
            .input('tipoMaterial', sql.NVarChar(5), final.tipoMaterial)
            .input('numeroPasadasPrensa', sql.SmallInt, final.numeroPasadasPrensa === null ? null : Number(final.numeroPasadasPrensa));
        for (const [clave, , max] of CAMPOS_PALLET) rq.input(clave, sql.NVarChar(largoSql(max)), norm(final[clave]));
        await rq.query(
            `UPDATE registros_calidad_faret_pallet SET
               tipo_material = @tipoMaterial, dimension = @dimension, fibra = @fibra, numero_pallet = @numeroPallet,
               numero_pasadas_prensa = @numeroPasadasPrensa, observaciones = @observaciones, area_control = @areaControl,
               operador = @operador, operador_otro = @operadorOtro, maquina = @maquina
             WHERE id = @id AND eliminado = 0`);

        for (const { pid, n } of respCambiadas) {
            await new sql.Request(transaction)
                .input('id', sql.Int, id).input('pid', sql.Int, pid)
                .input('resultado', sql.NVarChar(9), n.resultado).input('observacion', sql.NVarChar(MAX), n.observacion)
                .query('UPDATE registro_calidad_faret_pallet_respuestas SET resultado = @resultado, observacion = @observacion WHERE registro_id = @id AND pregunta_id = @pid');
        }

        await registrarAuditoria(transaction, { tipo: 'PALLET', registroId: id, cambios, motivo, usuario });
        await transaction.commit();
        res.json({ ok: true, message: 'Registro actualizado correctamente', data: { registroId: id, camposModificados: cambios.length } });
    } catch (error) {
        if (transaction) { try { await transaction.rollback(); } catch (_) { /* ya cerrada */ } }
        responderError(res, error, 'registro pallet/papel');
    }
};

// ---------------------------------------------------------------------------------------------------------------------
// Consulta de la bitácora
// ---------------------------------------------------------------------------------------------------------------------
const auditoriaDe = (tipo) => async (req, res) => {
    try {
        const id = idValido(req.params.id);
        const pool = await getCalidadSqlServerPool();
        res.json({ ok: true, data: await listarAuditoria(pool, tipo, id) });
    } catch (error) {
        if (error instanceof ErrorEdicion) return res.status(error.status).json({ ok: false, message: error.message });
        // Bitácora aún no creada (migración 011 pendiente): sin historial, no es un error para el usuario.
        if (error && error.number === 208) return res.json({ ok: true, data: [] });
        console.error('Error al consultar auditoría de inspecciones:', error.message);
        res.status(500).json({ ok: false, message: 'Error al consultar el historial de cambios' });
    }
};

module.exports = {
    actualizarRegistroCalidadFaret,
    actualizarRegistroCalidadFaretPallet,
    auditoriaCalidadFaret: auditoriaDe('CALIDAD'),
    auditoriaCalidadFaretPallet: auditoriaDe('PALLET'),
};
