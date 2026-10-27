const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const fs = require('fs');
const { borrarArchivos } = require('../utils/uploads');

const crearRegistroProductoTerminado = async (req, res) => {
    const poolConn = await getCalidadSqlServerPool();
    const transaction = new sql.Transaction(poolConn);

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
            empresa,
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
            !empresa ||
            !cantidadLote ||
            !turno ||
            !nivelInspeccion ||
            aql === undefined ||
            aql === null ||
            !letraCodigo ||
            !tamanoMuestra ||
            !resultado
        ) {
            borrarArchivos(req);
            return res.status(400).json({
                ok: false,
                message: 'Faltan datos obligatorios de la inspección',
            });
        }

        const hallazgosArray = Array.isArray(hallazgos) ? hallazgos : [];
        const archivos = Array.isArray(req.files) ? req.files : [];

        if (hallazgosArray.length !== archivos.length) {
            borrarArchivos(req);
            return res.status(400).json({
                ok: false,
                message:
                    'La cantidad de fotos no coincide con la cantidad de hallazgos (cada hallazgo requiere exactamente una foto)',
            });
        }

        await transaction.begin();

        const unidadesNc = hallazgosArray.length;
        const defectosTotales = hallazgosArray.reduce(
            (total, h) => total + (Array.isArray(h.defectoIds) ? h.defectoIds.length : 0),
            0
        );

        const registroResult = await new sql.Request(transaction)
            .input('usuarioId', sql.Int, usuarioId)
            .input('np', sql.NVarChar(50), np || null)
            .input('cliente', sql.NVarChar(255), cliente || null)
            .input('codigoProducto', sql.NVarChar(100), codigoProducto || null)
            .input('descripcionProducto', sql.NVarChar(255), descripcionProducto || null)
            .input('procesoPt', sql.NVarChar(12), procesoPt)
            .input('empresa', sql.NVarChar(7), empresa)
            .input('cantidadLote', sql.Int, cantidadLote)
            .input('cantidadPallets', sql.Int, cantidadPallets || null)
            .input('cantidadCajasBins', sql.Int, cantidadCajasBins || null)
            .input('maquina', sql.NVarChar(150), maquina || null)
            .input('turno', sql.NVarChar(1), turno)
            .input('nivelInspeccion', sql.NVarChar(3), nivelInspeccion)
            .input('aql', sql.Decimal(7, 3), aql)
            .input('letraCodigo', sql.NChar(1), letraCodigo)
            .input('tamanoMuestra', sql.Int, tamanoMuestra)
            .input('ac', sql.Int, ac ?? null)
            .input('re', sql.Int, re ?? null)
            .input('inspeccion100', sql.Bit, inspeccion100 ? 1 : 0)
            .input('unidadesNc', sql.Int, unidadesNc)
            .input('defectosTotales', sql.Int, defectosTotales)
            .input('resultado', sql.NVarChar(11), resultado)
            .query(
                `
            INSERT INTO registros_producto_terminado
            (
              usuario_id,
              np,
              cliente,
              codigo_producto,
              descripcion_producto,
              proceso_pt,
              empresa,
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
            OUTPUT INSERTED.id
            VALUES (@usuarioId, @np, @cliente, @codigoProducto, @descripcionProducto, @procesoPt, @empresa,
              @cantidadLote, @cantidadPallets, @cantidadCajasBins, @maquina, @turno, @nivelInspeccion, @aql,
              @letraCodigo, @tamanoMuestra, @ac, @re, @inspeccion100, @unidadesNc, @defectosTotales, @resultado,
              CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))
            `
            );

        const registroId = registroResult.recordset[0].id;

        if (Array.isArray(pallets)) {
            for (const palletId of pallets) {
                if (!palletId || !String(palletId).trim()) continue;

                await new sql.Request(transaction)
                    .input('registroId', sql.Int, registroId)
                    .input('palletId', sql.NVarChar(100), String(palletId).trim())
                    .query(`INSERT INTO registro_pt_pallets (registro_id, pallet_id) VALUES (@registroId, @palletId)`);
            }
        }

        for (let i = 0; i < hallazgosArray.length; i++) {
            const hallazgo = hallazgosArray[i];
            const archivo = archivos[i];
            const rutaRelativa = `/uploads/producto_terminado/${archivo.filename}`;

            const hallazgoResult = await new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('correlativo', sql.Int, i + 1)
                .input('origenId', sql.Int, hallazgo.origenId)
                .input('observacion', sql.NVarChar(120), hallazgo.observacion || null)
                .input('fotoNombreOriginal', sql.NVarChar(255), archivo.originalname)
                .input('fotoNombreArchivo', sql.NVarChar(255), archivo.filename)
                .input('fotoRuta', sql.NVarChar(500), rutaRelativa)
                .query(
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
                OUTPUT INSERTED.id
                VALUES (@registroId, @correlativo, @origenId, @observacion, @fotoNombreOriginal,
                  @fotoNombreArchivo, @fotoRuta)
                `
                );

            const hallazgoId = hallazgoResult.recordset[0].id;
            const defectoIds = Array.isArray(hallazgo.defectoIds) ? hallazgo.defectoIds : [];

            for (const defectoId of defectoIds) {
                await new sql.Request(transaction)
                    .input('hallazgoId', sql.Int, hallazgoId)
                    .input('defectoId', sql.Int, defectoId)
                    .query(`INSERT INTO registro_pt_hallazgo_defectos (hallazgo_id, defecto_id) VALUES (@hallazgoId, @defectoId)`);
            }
        }

        await transaction.commit();

        res.status(201).json({
            ok: true,
            message: 'Inspección de Producto Terminado guardada correctamente',
            data: {
                registroId,
            },
        });
    } catch (error) {
        try {
            await transaction.rollback();
        } catch (_) { }

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
    }
};

const listarRegistrosProductoTerminado = async (req, res) => {
    try {
        const { fechaDesde, fechaHasta, procesoPt, resultado } = req.query;
        const page = Math.max(parseInt(req.query.page, 10) || 1, 1);
        const pageSize = Math.min(Math.max(parseInt(req.query.pageSize, 10) || 20, 1), 100);
        const offset = (page - 1) * pageSize;

        const condiciones = [];
        const inputs = [];

        if (fechaDesde) {
            condiciones.push('r.fecha_registro >= @fechaDesde');
            inputs.push({ name: 'fechaDesde', type: sql.Date, value: fechaDesde });
        }

        if (fechaHasta) {
            condiciones.push('r.fecha_registro <= @fechaHasta');
            inputs.push({ name: 'fechaHasta', type: sql.Date, value: fechaHasta });
        }

        if (procesoPt) {
            condiciones.push('r.proceso_pt = @procesoPt');
            inputs.push({ name: 'procesoPt', type: sql.NVarChar(12), value: procesoPt });
        }

        if (resultado) {
            condiciones.push('r.resultado = @resultado');
            inputs.push({ name: 'resultado', type: sql.NVarChar(11), value: resultado });
        }

        const whereSql = condiciones.length ? `WHERE ${condiciones.join(' AND ')}` : '';

        const poolConn = await getCalidadSqlServerPool();

        const aplicarInputs = (request) => {
            for (const i of inputs) {
                request.input(i.name, i.type, i.value);
            }
            return request;
        };

        const rowsResult = await aplicarInputs(poolConn.request())
            .input('pageSize', sql.Int, pageSize)
            .input('offset', sql.Int, offset)
            .query(
                `
            SELECT
              r.id, r.np, r.cliente, r.codigo_producto, r.descripcion_producto,
              r.proceso_pt, r.empresa, r.cantidad_lote, r.cantidad_pallets, r.cantidad_cajas_bins,
              r.maquina, r.turno, r.nivel_inspeccion, r.aql, r.letra_codigo,
              r.tamano_muestra, r.ac, r.re, r.inspeccion_100, r.unidades_nc,
              r.defectos_totales, r.resultado, r.fecha_registro, r.hora_registro,
              u.nombre_completo AS inspector
            FROM registros_producto_terminado r
            LEFT JOIN usuarios u ON u.id = r.usuario_id
            ${whereSql}
            ORDER BY r.id DESC
            OFFSET @offset ROWS FETCH NEXT @pageSize ROWS ONLY
            `
            );

        const totalResult = await aplicarInputs(poolConn.request()).query(
            `SELECT COUNT(*) AS total FROM registros_producto_terminado r ${whereSql}`
        );

        res.json({
            ok: true,
            data: rowsResult.recordset,
            pagination: { page, pageSize, total: totalResult.recordset[0].total },
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

        const poolConn = await getCalidadSqlServerPool();

        const registrosResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                `
            SELECT
              r.*, u.nombre_completo AS inspector
            FROM registros_producto_terminado r
            LEFT JOIN usuarios u ON u.id = r.usuario_id
            WHERE r.id = @id
            `
            );
        const registros = registrosResult.recordset;

        if (registros.length === 0) {
            return res.status(404).json({ ok: false, message: 'Registro no encontrado' });
        }

        const palletsResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query('SELECT id, pallet_id FROM registro_pt_pallets WHERE registro_id = @id');

        const hallazgosResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                `
            SELECT
              h.id, h.correlativo, h.origen_id, o.nombre AS origen_nombre,
              h.observacion, h.foto_nombre_original, h.foto_ruta
            FROM registro_pt_hallazgos h
            LEFT JOIN origenes_problema o ON o.id = h.origen_id
            WHERE h.registro_id = @id
            ORDER BY h.correlativo ASC
            `
            );
        const hallazgos = hallazgosResult.recordset;

        for (const hallazgo of hallazgos) {
            const defectosResult = await poolConn.request()
                .input('hallazgoId', sql.Int, hallazgo.id)
                .query(
                    `
                SELECT d.id, p.nombre
                FROM registro_pt_hallazgo_defectos d
                LEFT JOIN parametros_control_visual p ON p.id = d.defecto_id
                WHERE d.hallazgo_id = @hallazgoId
                `
                );
            hallazgo.defectos = defectosResult.recordset;
        }

        res.json({
            ok: true,
            data: {
                ...registros[0],
                pallets: palletsResult.recordset,
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
