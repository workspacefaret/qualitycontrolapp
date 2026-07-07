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
            areaControl,
            operador,
            operadorOtro,
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
              area_control,
              operador,
              operador_otro,
              maquina,
              presenta_defectos,
              area_defecto,
              tipo_folia,
              accion_correctiva,
              fecha_registro,
              hora_registro
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), CURTIME())
            `,
            [
                nvFaret,
                nvVoBoAprobado ? 1 : 0,
                nPliego || null,
                nPasada || null,
                nItem || null,
                pliegoControlN || null,
                areaControl,
                operador,
                operadorOtro || null,
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

module.exports = {
    crearRegistroCalidadFaret,
};
