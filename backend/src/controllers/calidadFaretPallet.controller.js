const pool = require('../config/database');

const TIPOS_MATERIAL_VALIDOS = ['NV', 'PAPEL'];
const RESULTADOS_VALIDOS = ['CUMPLE', 'NO_CUMPLE'];

const crearRegistroCalidadFaretPallet = async (req, res) => {
    const connection = await pool.getConnection();

    try {
        const body = req.body || {};

        const {
            tipoMaterial,
            dimension,
            fibra,
            numeroPallet,
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

        const [preguntasActivas] = await connection.query(
            'SELECT id FROM calidad_faret_pallet_preguntas WHERE activo = 1'
        );

        const idsActivos = new Set(preguntasActivas.map((p) => p.id));

        if (idsUnicos.size !== idsActivos.size || [...idsActivos].some((id) => !idsUnicos.has(id))) {
            return res.status(400).json({
                ok: false,
                message: 'El checklist debe responder exactamente todas las preguntas activas',
            });
        }

        await connection.beginTransaction();

        const [registroResult] = await connection.query(
            `
            INSERT INTO registros_calidad_faret_pallet
            (
              tipo_material,
              dimension,
              fibra,
              numero_pallet,
              area_control,
              operador,
              operador_otro,
              maquina,
              fecha_registro,
              hora_registro
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), CURTIME())
            `,
            [
                tipoMaterial,
                String(dimension).trim(),
                fibra ? String(fibra).trim() : null,
                String(numeroPallet).trim(),
                areaControl || null,
                operador || null,
                operadorOtro || null,
                maquina || null,
            ]
        );

        const registroId = registroResult.insertId;

        if (operador && String(operador).trim()) {
            await connection.query(
                'INSERT IGNORE INTO calidad_faret_operadores (nombre) VALUES (?)',
                [String(operador).trim()]
            );
        }

        for (const respuesta of respuestas) {
            await connection.query(
                `
                INSERT INTO registro_calidad_faret_pallet_respuestas
                (registro_id, pregunta_id, resultado, observacion)
                VALUES (?, ?, ?, ?)
                `,
                [
                    registroId,
                    Number(respuesta.preguntaId),
                    respuesta.resultado,
                    respuesta.observacion ? String(respuesta.observacion).trim() : null,
                ]
            );
        }

        await connection.commit();

        res.status(201).json({
            ok: true,
            message: 'Registro de control pallet/papel guardado correctamente',
            data: {
                registroId,
            },
        });
    } catch (error) {
        await connection.rollback();

        console.error('Error al guardar registro pallet/papel:', error);

        res.status(500).json({
            ok: false,
            message: 'Error al guardar registro',
            error: error.message,
        });
    } finally {
        connection.release();
    }
};

const listarPreguntasCalidadFaretPallet = async (req, res) => {
    try {
        const [preguntas] = await pool.query(
            `
            SELECT id, texto, orden
            FROM calidad_faret_pallet_preguntas
            WHERE activo = 1
            ORDER BY orden ASC, id ASC
            `
        );

        res.json({ ok: true, data: preguntas });
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

    const condiciones = [];
    const params = [];

    if (fechaDesde) {
        condiciones.push('r.fecha_registro >= ?');
        params.push(fechaDesde);
    }

    if (fechaHasta) {
        condiciones.push('r.fecha_registro <= ?');
        params.push(fechaHasta);
    }

    if (tipoMaterial) {
        condiciones.push('r.tipo_material = ?');
        params.push(tipoMaterial);
    }

    if (numeroPallet) {
        condiciones.push('r.numero_pallet LIKE ?');
        params.push(`%${numeroPallet}%`);
    }

    if (maquina) {
        condiciones.push('r.maquina LIKE ?');
        params.push(`%${maquina}%`);
    }

    if (operador) {
        condiciones.push('r.operador LIKE ?');
        params.push(`%${operador}%`);
    }

    return {
        whereSql: condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '',
        params,
    };
};

const listarRegistrosCalidadFaretPallet = async (req, res) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pageSize, 10) || 50));
        const offset = (page - 1) * pageSize;

        const { whereSql, params } = buildFiltrosPallet(req.query);

        const [countRows] = await pool.query(
            `SELECT COUNT(*) AS total FROM registros_calidad_faret_pallet r ${whereSql}`,
            params
        );

        const [rows] = await pool.query(
            `
            SELECT
              r.id,
              r.tipo_material AS tipoMaterial,
              r.dimension,
              r.fibra,
              r.numero_pallet AS numeroPallet,
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
              ) AS totalNoCumple
            FROM registros_calidad_faret_pallet r
            ${whereSql}
            ORDER BY r.fecha_registro DESC, r.hora_registro DESC
            LIMIT ? OFFSET ?
            `,
            [...params, pageSize, offset]
        );

        res.json({
            ok: true,
            data: {
                items: rows,
                totalCount: countRows[0].total,
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

        const [registros] = await pool.query(
            `
            SELECT
              r.id,
              r.tipo_material AS tipoMaterial,
              r.dimension,
              r.fibra,
              r.numero_pallet AS numeroPallet,
              r.area_control AS areaControl,
              r.operador,
              r.operador_otro AS operadorOtro,
              r.maquina,
              r.fecha_registro AS fechaRegistro,
              r.hora_registro AS horaRegistro
            FROM registros_calidad_faret_pallet r
            WHERE r.id = ?
            `,
            [id]
        );

        if (registros.length === 0) {
            return res.status(404).json({
                ok: false,
                message: 'Registro no encontrado',
            });
        }

        const [respuestas] = await pool.query(
            `
            SELECT
              resp.pregunta_id AS preguntaId,
              p.texto,
              resp.resultado,
              resp.observacion
            FROM registro_calidad_faret_pallet_respuestas resp
            INNER JOIN calidad_faret_pallet_preguntas p ON p.id = resp.pregunta_id
            WHERE resp.registro_id = ?
            ORDER BY p.orden ASC, p.id ASC
            `,
            [id]
        );

        res.json({
            ok: true,
            data: {
                ...registros[0],
                respuestas,
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

module.exports = {
    crearRegistroCalidadFaretPallet,
    listarPreguntasCalidadFaretPallet,
    listarRegistrosCalidadFaretPallet,
    obtenerRegistroCalidadFaretPallet,
};
