const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const { auditoriaDisponible, resumenEdicionSql } = require('../utils/edicionInspecciones');

const TIPOS_MATERIAL_VALIDOS = ['NV', 'PAPEL'];
const RESULTADOS_VALIDOS = ['CUMPLE', 'NO_CUMPLE'];

const crearRegistroCalidadFaretPallet = async (req, res) => {
    const poolConn = await getCalidadSqlServerPool();
    const transaction = new sql.Transaction(poolConn);

    try {
        const body = req.body || {};

        const {
            tipoMaterial,
            dimension,
            fibra,
            numeroPallet,
            numeroPasadasPrensa,
            observaciones,
            areaControl,
            operador,
            operadorOtro,
            maquina,
            respuestas,
        } = body;

        if (!tipoMaterial || !TIPOS_MATERIAL_VALIDOS.includes(tipoMaterial)) {
            return res.status(400).json({
                ok: false,
                message: 'Tipo de material inválido. Debe ser NV o PAPEL',
            });
        }

        if (!dimension || !String(dimension).trim()) {
            return res.status(400).json({
                ok: false,
                message: 'La dimensión es obligatoria',
            });
        }

        if (!numeroPallet || !String(numeroPallet).trim()) {
            return res.status(400).json({
                ok: false,
                message: 'El número de pallet es obligatorio',
            });
        }

        if (
            numeroPasadasPrensa !== undefined &&
            numeroPasadasPrensa !== null &&
            ![1, 2, 3].includes(Number(numeroPasadasPrensa))
        ) {
            return res.status(400).json({
                ok: false,
                message: 'El número de pasadas de prensa debe ser 1, 2 o 3',
            });
        }

        if (!Array.isArray(respuestas) || respuestas.length === 0) {
            return res.status(400).json({
                ok: false,
                message: 'El checklist de respuestas es obligatorio',
            });
        }

        const preguntaIds = respuestas.map((r) => Number(r.preguntaId));

        if (preguntaIds.some((id) => !Number.isInteger(id))) {
            return res.status(400).json({
                ok: false,
                message: 'Hay respuestas con preguntaId inválido',
            });
        }

        const idsUnicos = new Set(preguntaIds);

        if (idsUnicos.size !== preguntaIds.length) {
            return res.status(400).json({
                ok: false,
                message: 'El checklist tiene preguntas duplicadas',
            });
        }

        for (const respuesta of respuestas) {
            if (!RESULTADOS_VALIDOS.includes(respuesta.resultado)) {
                return res.status(400).json({
                    ok: false,
                    message: `Resultado inválido para preguntaId ${respuesta.preguntaId}`,
                });
            }

            if (
                respuesta.resultado === 'NO_CUMPLE' &&
                (!respuesta.observacion || !String(respuesta.observacion).trim())
            ) {
                return res.status(400).json({
                    ok: false,
                    message: `Falta observación obligatoria para la respuesta NO_CUMPLE de preguntaId ${respuesta.preguntaId}`,
                });
            }
        }

        const preguntasActivasResult = await poolConn.request().query(
            'SELECT id FROM calidad_faret_pallet_preguntas WHERE activo = 1'
        );
        const preguntasActivas = preguntasActivasResult.recordset;

        const idsActivos = new Set(preguntasActivas.map((p) => p.id));

        if (idsUnicos.size !== idsActivos.size || [...idsActivos].some((id) => !idsUnicos.has(id))) {
            return res.status(400).json({
                ok: false,
                message: 'El checklist debe responder exactamente todas las preguntas activas',
            });
        }

        await transaction.begin();

        const registroResult = await new sql.Request(transaction)
            .input('tipoMaterial', sql.NVarChar(5), tipoMaterial)
            .input('dimension', sql.NVarChar(100), String(dimension).trim())
            .input('fibra', sql.NVarChar(50), fibra ? String(fibra).trim() : null)
            .input('numeroPallet', sql.NVarChar(100), String(numeroPallet).trim())
            .input('numeroPasadasPrensa', sql.SmallInt, numeroPasadasPrensa ? Number(numeroPasadasPrensa) : null)
            .input('observaciones', sql.NVarChar(sql.MAX), observaciones ? String(observaciones).trim() : null)
            .input('areaControl', sql.NVarChar(100), areaControl || null)
            .input('operador', sql.NVarChar(150), operador || null)
            .input('operadorOtro', sql.NVarChar(150), operadorOtro || null)
            .input('maquina', sql.NVarChar(150), maquina || null)
            .query(
                `
            INSERT INTO registros_calidad_faret_pallet
            (
              tipo_material,
              dimension,
              fibra,
              numero_pallet,
              numero_pasadas_prensa,
              observaciones,
              area_control,
              operador,
              operador_otro,
              maquina,
              fecha_registro,
              hora_registro
            )
            OUTPUT INSERTED.id
            VALUES (@tipoMaterial, @dimension, @fibra, @numeroPallet, @numeroPasadasPrensa, @observaciones,
              @areaControl, @operador, @operadorOtro, @maquina, CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))
            `
            );

        const registroId = registroResult.recordset[0].id;

        if (operador && String(operador).trim()) {
            try {
                await new sql.Request(transaction)
                    .input('nombre', sql.NVarChar(150), String(operador).trim())
                    .query(
                        `
                        IF NOT EXISTS (SELECT 1 FROM calidad_faret_operadores WHERE nombre = @nombre)
                        BEGIN
                            INSERT INTO calidad_faret_operadores (nombre) VALUES (@nombre)
                        END
                        `
                    );
            } catch (errorOperador) {
                if (errorOperador.number !== 2627 && errorOperador.number !== 2601) {
                    throw errorOperador;
                }
            }
        }

        for (const respuesta of respuestas) {
            await new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('preguntaId', sql.Int, Number(respuesta.preguntaId))
                .input('resultado', sql.NVarChar(9), respuesta.resultado)
                .input('observacion', sql.NVarChar(sql.MAX), respuesta.observacion ? String(respuesta.observacion).trim() : null)
                .query(
                    `
                INSERT INTO registro_calidad_faret_pallet_respuestas
                (registro_id, pregunta_id, resultado, observacion)
                VALUES (@registroId, @preguntaId, @resultado, @observacion)
                `
                );
        }

        await transaction.commit();

        res.status(201).json({
            ok: true,
            message: 'Registro de control pallet/papel guardado correctamente',
            data: {
                registroId,
            },
        });
    } catch (error) {
        try {
            await transaction.rollback();
        } catch (_) { }

        console.error('Error al guardar registro pallet/papel:', error);

        res.status(500).json({
            ok: false,
            message: 'Error al guardar registro',
            error: error.message,
        });
    }
};

const listarPreguntasCalidadFaretPallet = async (req, res) => {
    try {
        const poolConn = await getCalidadSqlServerPool();
        const result = await poolConn.request().query(
            `
            SELECT id, texto, orden
            FROM calidad_faret_pallet_preguntas
            WHERE activo = 1
            ORDER BY orden ASC, id ASC
            `
        );

        res.json({ ok: true, data: result.recordset });
    } catch (error) {
        console.error('Error al listar preguntas pallet/papel:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar preguntas',
            error: error.message,
        });
    }
};

const buildFiltrosPallet = (query) => {
    const { fechaDesde, fechaHasta, tipoMaterial, numeroPallet, maquina, operador } = query;

    const condiciones = ['r.eliminado = 0'];
    const inputs = [];

    if (fechaDesde) {
        condiciones.push('r.fecha_registro >= @fechaDesde');
        inputs.push({ name: 'fechaDesde', type: sql.Date, value: fechaDesde });
    }

    if (fechaHasta) {
        condiciones.push('r.fecha_registro <= @fechaHasta');
        inputs.push({ name: 'fechaHasta', type: sql.Date, value: fechaHasta });
    }

    if (tipoMaterial) {
        condiciones.push('r.tipo_material = @tipoMaterial');
        inputs.push({ name: 'tipoMaterial', type: sql.NVarChar(5), value: tipoMaterial });
    }

    if (numeroPallet) {
        condiciones.push('r.numero_pallet LIKE @numeroPallet');
        inputs.push({ name: 'numeroPallet', type: sql.NVarChar(100), value: `%${numeroPallet}%` });
    }

    if (maquina) {
        condiciones.push('r.maquina LIKE @maquina');
        inputs.push({ name: 'maquina', type: sql.NVarChar(150), value: `%${maquina}%` });
    }

    if (operador) {
        condiciones.push('r.operador LIKE @operador');
        inputs.push({ name: 'operador', type: sql.NVarChar(150), value: `%${operador}%` });
    }

    return {
        whereSql: condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '',
        inputs,
    };
};

const aplicarInputs = (request, inputs) => {
    for (const i of inputs) {
        request.input(i.name, i.type, i.value);
    }

    return request;
};

const listarRegistrosCalidadFaretPallet = async (req, res) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pageSize, 10) || 50));
        const offset = (page - 1) * pageSize;

        const { whereSql, inputs } = buildFiltrosPallet(req.query);
        const poolConn = await getCalidadSqlServerPool();

        const countResult = await aplicarInputs(poolConn.request(), inputs).query(
            `SELECT COUNT(*) AS total FROM registros_calidad_faret_pallet r ${whereSql}`
        );

        const edicionSql = (await auditoriaDisponible(poolConn)) ? resumenEdicionSql('PALLET') : '';
        const rowsResult = await aplicarInputs(poolConn.request(), inputs)
            .input('pageSize', sql.Int, pageSize)
            .input('offset', sql.Int, offset)
            .query(
                `
            SELECT
              r.id,
              r.tipo_material AS tipoMaterial,
              r.dimension,
              r.fibra,
              r.numero_pallet AS numeroPallet,
              r.numero_pasadas_prensa AS numeroPasadasPrensa,
              r.observaciones,
              r.area_control AS areaControl,
              r.operador,
              r.operador_otro AS operadorOtro,
              r.maquina,
              r.fecha_registro AS fechaRegistro,
              r.hora_registro AS horaRegistro,
              (
                SELECT COUNT(*)
                FROM registro_calidad_faret_pallet_respuestas resp
                WHERE resp.registro_id = r.id AND resp.resultado = 'NO_CUMPLE'
              ) AS totalNoCumple${edicionSql}
            FROM registros_calidad_faret_pallet r
            ${whereSql}
            ORDER BY r.fecha_registro DESC, r.hora_registro DESC
            OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
            `
            );

        res.json({
            ok: true,
            data: {
                items: rowsResult.recordset,
                totalCount: countResult.recordset[0].total,
                page,
                pageSize,
            },
        });
    } catch (error) {
        console.error('Error al listar registros pallet/papel:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar registros',
            error: error.message,
        });
    }
};

const obtenerRegistroCalidadFaretPallet = async (req, res) => {
    try {
        const { id } = req.params;

        const poolConn = await getCalidadSqlServerPool();

        const registrosResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                `
            SELECT
              r.id,
              r.tipo_material AS tipoMaterial,
              r.dimension,
              r.fibra,
              r.numero_pallet AS numeroPallet,
              r.numero_pasadas_prensa AS numeroPasadasPrensa,
              r.observaciones,
              r.area_control AS areaControl,
              r.operador,
              r.operador_otro AS operadorOtro,
              r.maquina,
              r.fecha_registro AS fechaRegistro,
              r.hora_registro AS horaRegistro
            FROM registros_calidad_faret_pallet r
            WHERE r.id = @id AND r.eliminado = 0
            `
            );
        const registros = registrosResult.recordset;

        if (registros.length === 0) {
            return res.status(404).json({
                ok: false,
                message: 'Registro no encontrado',
            });
        }

        const respuestasResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                `
            SELECT
              resp.pregunta_id AS preguntaId,
              p.texto,
              resp.resultado,
              resp.observacion
            FROM registro_calidad_faret_pallet_respuestas resp
            INNER JOIN calidad_faret_pallet_preguntas p ON p.id = resp.pregunta_id
            WHERE resp.registro_id = @id
            ORDER BY p.orden ASC, p.id ASC
            `
            );

        res.json({
            ok: true,
            data: {
                ...registros[0],
                respuestas: respuestasResult.recordset,
            },
        });
    } catch (error) {
        console.error('Error al obtener registro pallet/papel:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener registro',
            error: error.message,
        });
    }
};

const eliminarRegistroCalidadFaretPallet = async (req, res) => {
    try {
        const { id } = req.params;

        const poolConn = await getCalidadSqlServerPool();
        const resultado = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                'UPDATE registros_calidad_faret_pallet SET eliminado = 1 WHERE id = @id AND eliminado = 0'
            );

        if (resultado.rowsAffected[0] === 0) {
            return res.status(404).json({
                ok: false,
                message: 'Registro no encontrado',
            });
        }

        res.json({ ok: true, message: 'Registro eliminado correctamente', data: {} });
    } catch (error) {
        console.error('Error al eliminar registro pallet/papel:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al eliminar el registro',
            error: error.message,
        });
    }
};

module.exports = {
    crearRegistroCalidadFaretPallet,
    listarPreguntasCalidadFaretPallet,
    listarRegistrosCalidadFaretPallet,
    obtenerRegistroCalidadFaretPallet,
    eliminarRegistroCalidadFaretPallet,
};
