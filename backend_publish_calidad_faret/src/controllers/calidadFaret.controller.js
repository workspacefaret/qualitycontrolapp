const pool = require('../config/database');
const fs = require('fs');

const crearRegistroCalidadFaret = async (req, res) => {
    const connection = await pool.getConnection();

    try {
        let body = req.body;

        if (body.payload) {
            body = JSON.parse(body.payload);
        }

        const {
            nvFaret,
            nvVoBoAprobado,
            nPliego,
            nPasada,
            nItem,
            pliegoControlN,
            observaciones,
            areaControl,
            operador,
            operadorOtro,
            operadorRegistro,
            maquina,
            presentaDefectos,
            areaDefecto,
            defectos,
            tipoFolia,
            accionCorrectiva,
        } = body;

        if (!nvFaret || !areaControl || !operador || !maquina) {
            return res.status(400).json({
                ok: false,
                message: 'Faltan datos obligatorios del formulario',
            });
        }

        await connection.beginTransaction();

        const [registroResult] = await connection.query(
            `
            INSERT INTO registros_calidad_faret
            (
              nv_faret,
              nv_vb_aprobado,
              n_pliego,
              n_pasada,
              n_item,
              pliego_control_n,
              observaciones,
              area_control,
              operador,
              operador_otro,
              operador_registro,
              maquina,
              presenta_defectos,
              area_defecto,
              tipo_folia,
              accion_correctiva,
              fecha_registro,
              hora_registro
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), CURTIME())
            `,
            [
                nvFaret,
                nvVoBoAprobado ? 1 : 0,
                nPliego || null,
                nPasada || null,
                nItem || null,
                pliegoControlN || null,
                observaciones || null,
                areaControl,
                operador,
                operadorOtro || null,
                operadorRegistro || null,
                maquina,
                presentaDefectos ? 1 : 0,
                presentaDefectos ? areaDefecto || null : null,
                presentaDefectos ? tipoFolia || null : null,
                presentaDefectos ? accionCorrectiva || null : null,
            ]
        );

        const registroId = registroResult.insertId;

        if (presentaDefectos && Array.isArray(defectos) && defectos.length > 0) {
            for (const defecto of defectos) {
                await connection.query(
                    `
                    INSERT INTO registro_calidad_faret_defectos
                    (registro_id, defecto)
                    VALUES (?, ?)
                    `,
                    [registroId, defecto]
                );
            }
        }

        if (operadorRegistro && String(operadorRegistro).trim()) {
            await connection.query(
                'INSERT IGNORE INTO calidad_faret_operadores (nombre) VALUES (?)',
                [String(operadorRegistro).trim()]
            );
        }

        const archivos = Array.isArray(req.files) ? req.files : [];

        for (const archivo of archivos) {
            const rutaRelativa = `/uploads/calidad_faret/${archivo.filename}`;

            await connection.query(
                `
                INSERT INTO registro_calidad_faret_adjuntos
                (
                  registro_id,
                  nombre_original,
                  nombre_archivo,
                  ruta_archivo,
                  mime_type,
                  tamano_bytes
                )
                VALUES (?, ?, ?, ?, ?, ?)
                `,
                [
                    registroId,
                    archivo.originalname,
                    archivo.filename,
                    rutaRelativa,
                    archivo.mimetype,
                    archivo.size,
                ]
            );
        }

        await connection.commit();

        res.status(201).json({
            ok: true,
            message: 'Registro de calidad Faret guardado correctamente',
            data: {
                registroId,
            },
        });
    } catch (error) {
        await connection.rollback();

        if (Array.isArray(req.files)) {
            for (const archivo of req.files) {
                try {
                    fs.unlinkSync(archivo.path);
                } catch (_) { }
            }
        }

        console.error('Error al guardar registro calidad Faret:', error);

        res.status(500).json({
            ok: false,
            message: 'Error al guardar registro',
            error: error.message,
        });
    } finally {
        connection.release();
    }
};

const buildFiltros = (query) => {
    const { fechaDesde, fechaHasta, areaControl, operador, maquina, presentaDefectos, nvFaret } = query;

    const condiciones = ['r.eliminado = 0'];
    const params = [];

    if (fechaDesde) {
        condiciones.push('r.fecha_registro >= ?');
        params.push(fechaDesde);
    }

    if (fechaHasta) {
        condiciones.push('r.fecha_registro <= ?');
        params.push(fechaHasta);
    }

    if (areaControl) {
        condiciones.push('r.area_control = ?');
        params.push(areaControl);
    }

    if (nvFaret) {
        condiciones.push('r.nv_faret LIKE ?');
        params.push(`%${nvFaret}%`);
    }

    if (operador) {
        condiciones.push('r.operador LIKE ?');
        params.push(`%${operador}%`);
    }

    if (maquina) {
        condiciones.push('r.maquina LIKE ?');
        params.push(`%${maquina}%`);
    }

    if (presentaDefectos === 'true' || presentaDefectos === '1') {
        condiciones.push('r.presenta_defectos = 1');
    } else if (presentaDefectos === 'false' || presentaDefectos === '0') {
        condiciones.push('r.presenta_defectos = 0');
    }

    return {
        whereSql: condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '',
        params,
    };
};

const listarRegistrosCalidadFaret = async (req, res) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pageSize, 10) || 50));
        const offset = (page - 1) * pageSize;

        const { whereSql, params } = buildFiltros(req.query);

        const [countRows] = await pool.query(
            `SELECT COUNT(*) AS total FROM registros_calidad_faret r ${whereSql}`,
            params
        );

        const [rows] = await pool.query(
            `
            SELECT
              r.id,
              r.nv_faret AS nvFaret,
              r.nv_vb_aprobado AS nvVoBoAprobado,
              r.n_pliego AS nPliego,
              r.n_pasada AS nPasada,
              r.n_item AS nItem,
              r.pliego_control_n AS pliegoControlN,
              r.observaciones,
              r.area_control AS areaControl,
              r.operador,
              r.operador_otro AS operadorOtro,
              r.operador_registro AS operadorRegistro,
              r.maquina,
              r.presenta_defectos AS presentaDefectos,
              r.area_defecto AS areaDefecto,
              r.tipo_folia AS tipoFolia,
              r.accion_correctiva AS accionCorrectiva,
              r.fecha_registro AS fechaRegistro,
              r.hora_registro AS horaRegistro,
              (
                SELECT GROUP_CONCAT(d.defecto SEPARATOR ', ')
                FROM registro_calidad_faret_defectos d
                WHERE d.registro_id = r.id
              ) AS defectos,
              (
                SELECT COUNT(*)
                FROM registro_calidad_faret_adjuntos a
                WHERE a.registro_id = r.id
              ) AS cantidadAdjuntos
            FROM registros_calidad_faret r
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
        console.error('Error al listar registros calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar registros',
            error: error.message,
        });
    }
};

const obtenerResumenCalidadFaret = async (req, res) => {
    try {
        const { whereSql, params } = buildFiltros(req.query);

        const [[resumen]] = await pool.query(
            `
            SELECT
              COUNT(*) AS inspecciones_periodo,
              SUM(CASE WHEN presenta_defectos = 1 THEN 1 ELSE 0 END) AS con_defectos,
              SUM(CASE WHEN presenta_defectos = 0 THEN 1 ELSE 0 END) AS sin_defectos
            FROM registros_calidad_faret r
            ${whereSql}
            `,
            params
        );

        const [[hoy]] = await pool.query(`
            SELECT COUNT(*) AS inspecciones_hoy
            FROM registros_calidad_faret
            WHERE fecha_registro = CURDATE()
        `);

        res.json({
            ok: true,
            data: {
                inspeccionesHoy: Number(hoy.inspecciones_hoy) || 0,
                inspeccionesPeriodo: Number(resumen.inspecciones_periodo) || 0,
                conDefectos: Number(resumen.con_defectos) || 0,
                sinDefectos: Number(resumen.sin_defectos) || 0,
            },
        });
    } catch (error) {
        console.error('Error al obtener resumen calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener resumen',
            error: error.message,
        });
    }
};

const obtenerResumenMaquinasCalidadFaret = async (req, res) => {
    try {
        const { maquina } = req.query;

        const [maquinas] = await pool.query(`
            SELECT
              maquina,
              area_control AS areaControl,
              COUNT(*) AS totalRegistros
            FROM registros_calidad_faret
            WHERE maquina IS NOT NULL AND maquina <> ''
            GROUP BY maquina, area_control
            ORDER BY area_control, maquina
        `);

        const data = {
            totalMaquinas: maquinas.length,
            maquinas,
            registrosMaquinaSeleccionada: 0,
            conDefectosMaquinaSeleccionada: 0,
            registros: [],
        };

        if (maquina) {
            const [[stats]] = await pool.query(
                `
                SELECT
                  COUNT(*) AS totalRegistros,
                  SUM(CASE WHEN presenta_defectos = 1 THEN 1 ELSE 0 END) AS conDefectos
                FROM registros_calidad_faret
                WHERE maquina = ?
                `,
                [maquina]
            );

            data.registrosMaquinaSeleccionada = Number(stats.totalRegistros) || 0;
            data.conDefectosMaquinaSeleccionada = Number(stats.conDefectos) || 0;

            const [registros] = await pool.query(
                `
                SELECT
                  r.id,
                  r.nv_faret AS nvFaret,
                  r.area_control AS areaControl,
                  r.operador,
                  r.operador_otro AS operadorOtro,
                  r.operador_registro AS operadorRegistro,
                  r.maquina,
                  r.presenta_defectos AS presentaDefectos,
                  r.accion_correctiva AS accionCorrectiva,
                  r.fecha_registro AS fechaRegistro,
                  r.hora_registro AS horaRegistro,
                  (
                    SELECT GROUP_CONCAT(d.defecto SEPARATOR ', ')
                    FROM registro_calidad_faret_defectos d
                    WHERE d.registro_id = r.id
                  ) AS defectos
                FROM registros_calidad_faret r
                WHERE r.maquina = ?
                ORDER BY r.fecha_registro DESC, r.hora_registro DESC
                LIMIT 100
                `,
                [maquina]
            );

            data.registros = registros;
        }

        res.json({ ok: true, data });
    } catch (error) {
        console.error('Error al obtener resumen de máquinas calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener resumen de máquinas',
            error: error.message,
        });
    }
};

const listarAdjuntosRegistroCalidadFaret = async (req, res) => {
    try {
        const { id } = req.params;

        const [adjuntos] = await pool.query(
            `
            SELECT
              id,
              nombre_original AS nombreOriginal,
              ruta_archivo AS rutaArchivo,
              mime_type AS mimeType
            FROM registro_calidad_faret_adjuntos
            WHERE registro_id = ?
            ORDER BY id ASC
            `,
            [id]
        );

        res.json({ ok: true, data: adjuntos });
    } catch (error) {
        console.error('Error al listar adjuntos de registro calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar adjuntos',
            error: error.message,
        });
    }
};

const eliminarRegistroCalidadFaret = async (req, res) => {
    try {
        const { id } = req.params;

        const [resultado] = await pool.query(
            'UPDATE registros_calidad_faret SET eliminado = 1 WHERE id = ? AND eliminado = 0',
            [id]
        );

        if (resultado.affectedRows === 0) {
            return res.status(404).json({
                ok: false,
                message: 'Registro no encontrado',
            });
        }

        res.json({ ok: true, message: 'Registro eliminado correctamente', data: {} });
    } catch (error) {
        console.error('Error al eliminar registro calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al eliminar el registro',
            error: error.message,
        });
    }
};

module.exports = {
    crearRegistroCalidadFaret,
    listarRegistrosCalidadFaret,
    obtenerResumenCalidadFaret,
    obtenerResumenMaquinasCalidadFaret,
    listarAdjuntosRegistroCalidadFaret,
    eliminarRegistroCalidadFaret,
};
