const pool = require('../config/database');
const fs = require('fs');

const crearRegistroProductoTerminado = async (req, res) => {
    const connection = await pool.getConnection();

    try {
        let body = req.body;

        if (body.payload) {
            body = JSON.parse(body.payload);
        }

        const {
            usuarioId,
            np,
            cliente,
            codigoProducto,
            descripcionProducto,
            procesoPt,
            cantidadLote,
            cantidadPallets,
            cantidadCajasBins,
            maquina,
            turno,
            nivelInspeccion,
            aql,
            letraCodigo,
            tamanoMuestra,
            ac,
            re,
            inspeccion100,
            resultado,
            pallets,
            hallazgos,
        } = body;

        if (
            !usuarioId ||
            !procesoPt ||
            !cantidadLote ||
            !turno ||
            !nivelInspeccion ||
            aql === undefined ||
            aql === null ||
            !letraCodigo ||
            !tamanoMuestra ||
            !resultado
        ) {
            return res.status(400).json({
                ok: false,
                message: 'Faltan datos obligatorios de la inspección',
            });
        }

        const hallazgosArray = Array.isArray(hallazgos) ? hallazgos : [];
        const archivos = Array.isArray(req.files) ? req.files : [];

        if (hallazgosArray.length !== archivos.length) {
            return res.status(400).json({
                ok: false,
                message:
                    'La cantidad de fotos no coincide con la cantidad de hallazgos (cada hallazgo requiere exactamente una foto)',
            });
        }

        await connection.beginTransaction();

        const [registroResult] = await connection.query(
            `
            INSERT INTO registros_producto_terminado
            (
              usuario_id,
              np,
              cliente,
              codigo_producto,
              descripcion_producto,
              proceso_pt,
              cantidad_lote,
              cantidad_pallets,
              cantidad_cajas_bins,
              maquina,
              turno,
              nivel_inspeccion,
              aql,
              letra_codigo,
              tamano_muestra,
              ac,
              re,
              inspeccion_100,
              unidades_nc,
              defectos_totales,
              resultado,
              fecha_registro,
              hora_registro
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURDATE(), CURTIME())
            `,
            [
                usuarioId,
                np || null,
                cliente || null,
                codigoProducto || null,
                descripcionProducto || null,
                procesoPt,
                cantidadLote,
                cantidadPallets || null,
                cantidadCajasBins || null,
                maquina || null,
                turno,
                nivelInspeccion,
                aql,
                letraCodigo,
                tamanoMuestra,
                ac ?? null,
                re ?? null,
                inspeccion100 ? 1 : 0,
                hallazgosArray.length,
                hallazgosArray.reduce(
                    (total, h) => total + (Array.isArray(h.defectoIds) ? h.defectoIds.length : 0),
                    0
                ),
                resultado,
            ]
        );

        const registroId = registroResult.insertId;

        if (Array.isArray(pallets)) {
            for (const palletId of pallets) {
                if (!palletId || !String(palletId).trim()) continue;

                await connection.query(
                    `INSERT INTO registro_pt_pallets (registro_id, pallet_id) VALUES (?, ?)`,
                    [registroId, String(palletId).trim()]
                );
            }
        }

        for (let i = 0; i < hallazgosArray.length; i++) {
            const hallazgo = hallazgosArray[i];
            const archivo = archivos[i];
            const rutaRelativa = `/uploads/producto_terminado/${archivo.filename}`;

            const [hallazgoResult] = await connection.query(
                `
                INSERT INTO registro_pt_hallazgos
                (
                  registro_id,
                  correlativo,
                  origen_id,
                  observacion,
                  foto_nombre_original,
                  foto_nombre_archivo,
                  foto_ruta
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                `,
                [
                    registroId,
                    i + 1,
                    hallazgo.origenId,
                    hallazgo.observacion || null,
                    archivo.originalname,
                    archivo.filename,
                    rutaRelativa,
                ]
            );

            const hallazgoId = hallazgoResult.insertId;
            const defectoIds = Array.isArray(hallazgo.defectoIds) ? hallazgo.defectoIds : [];

            for (const defectoId of defectoIds) {
                await connection.query(
                    `INSERT INTO registro_pt_hallazgo_defectos (hallazgo_id, defecto_id) VALUES (?, ?)`,
                    [hallazgoId, defectoId]
                );
            }
        }

        await connection.commit();

        res.status(201).json({
            ok: true,
            message: 'Inspección de Producto Terminado guardada correctamente',
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

        console.error('Error al guardar registro Producto Terminado:', error);

        res.status(500).json({
            ok: false,
            message: 'Error al guardar inspección',
            error: error.message,
        });
    } finally {
        connection.release();
    }
};

const listarRegistrosProductoTerminado = async (req, res) => {
    try {
        const { fechaDesde, fechaHasta, procesoPt, resultado } = req.query;
        const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
        const pageSize = Math.min(Math.max(parseInt(req.query.pageSize, 10) || 20, 1), 100);
        const offset = (page - 1) * pageSize;

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

        if (procesoPt) {
            condiciones.push('r.proceso_pt = ?');
            params.push(procesoPt);
        }

        if (resultado) {
            condiciones.push('r.resultado = ?');
            params.push(resultado);
        }

        const whereSql = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';

        const [rows] = await pool.query(
            `
            SELECT
              r.id, r.np, r.cliente, r.codigo_producto, r.descripcion_producto,
              r.proceso_pt, r.cantidad_lote, r.cantidad_pallets, r.cantidad_cajas_bins,
              r.maquina, r.turno, r.nivel_inspeccion, r.aql, r.letra_codigo,
              r.tamano_muestra, r.ac, r.re, r.inspeccion_100, r.unidades_nc,
              r.defectos_totales, r.resultado, r.fecha_registro, r.hora_registro,
              u.nombre_completo AS inspector
            FROM registros_producto_terminado r
            LEFT JOIN usuarios u ON u.id = r.usuario_id
            ${whereSql}
            ORDER BY r.id DESC
            LIMIT ? OFFSET ?
            `,
            [...params, pageSize, offset]
        );

        const [[{ total }]] = await pool.query(
            `SELECT COUNT(*) AS total FROM registros_producto_terminado r ${whereSql}`,
            params
        );

        res.json({
            ok: true,
            data: rows,
            pagination: { page, pageSize, total },
        });
    } catch (error) {
        console.error('Error al listar registros Producto Terminado:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar registros',
            error: error.message,
        });
    }
};

const obtenerRegistroProductoTerminado = async (req, res) => {
    try {
        const { id } = req.params;

        const [registros] = await pool.query(
            `
            SELECT
              r.*, u.nombre_completo AS inspector
            FROM registros_producto_terminado r
            LEFT JOIN usuarios u ON u.id = r.usuario_id
            WHERE r.id = ?
            `,
            [id]
        );

        if (registros.length === 0) {
            return res.status(404).json({ ok: false, message: 'Registro no encontrado' });
        }

        const [pallets] = await pool.query(
            'SELECT id, pallet_id FROM registro_pt_pallets WHERE registro_id = ?',
            [id]
        );

        const [hallazgos] = await pool.query(
            `
            SELECT
              h.id, h.correlativo, h.origen_id, o.nombre AS origen_nombre,
              h.observacion, h.foto_nombre_original, h.foto_ruta
            FROM registro_pt_hallazgos h
            LEFT JOIN origenes_problema o ON o.id = h.origen_id
            WHERE h.registro_id = ?
            ORDER BY h.correlativo ASC
            `,
            [id]
        );

        for (const hallazgo of hallazgos) {
            const [defectos] = await pool.query(
                `
                SELECT d.id, p.nombre
                FROM registro_pt_hallazgo_defectos d
                LEFT JOIN parametros_control_visual p ON p.id = d.defecto_id
                WHERE d.hallazgo_id = ?
                `,
                [hallazgo.id]
            );
            hallazgo.defectos = defectos;
        }

        res.json({
            ok: true,
            data: {
                ...registros[0],
                pallets,
                hallazgos,
            },
        });
    } catch (error) {
        console.error('Error al obtener registro Producto Terminado:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener registro',
            error: error.message,
        });
    }
};

module.exports = {
    crearRegistroProductoTerminado,
    listarRegistrosProductoTerminado,
    obtenerRegistroProductoTerminado,
};
