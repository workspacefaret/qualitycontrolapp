const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const { borrarArchivos, normalizarClientId } = require('../utils/uploads');


const getContextoPorQr = async (req, res) => {
    try {
        const { codigoQr } = req.params;

        const poolConn = await getCalidadSqlServerPool();

        const rowsResult = await poolConn.request()
            .input('codigoQr', sql.NVarChar, codigoQr)
            .query(
                `
      SELECT
        m.id AS machineId,
        m.nombre AS machineName,
        m.codigo_qr AS codigoQr,
        p.id AS processId,
        p.nombre AS processName,
        f.id AS formId,
        f.nombre AS formName
      FROM maquinas m
      INNER JOIN procesos p ON p.id = m.proceso_id
      LEFT JOIN formularios_control f
        ON f.proceso_id = p.id
        AND f.activo = 1
        AND f.maquina_id IS NULL
      WHERE m.codigo_qr = @codigoQr
        AND m.activo = 1
      `
            );
        const rows = rowsResult.recordset;

        if (rows.length === 0) {
            return res.status(404).json({
                ok: false,
                message: 'QR no encontrado o máquina inactiva',
            });
        }

        const tiposOndaResult = await poolConn.request().query(
            `
            SELECT
              id,
              nombre
            FROM tipos_onda
            WHERE activo = 1
            ORDER BY nombre ASC
            `
        );
        const tiposOnda = tiposOndaResult.recordset;

        const materialesResult = await poolConn.request().query(
            `
            SELECT
              id,
              nombre
            FROM materiales
            WHERE activo = 1
            ORDER BY nombre ASC
            `
        );
        const materiales = materialesResult.recordset;

        const ensayosLaboratorioResult = await poolConn.request().query(
            `
            SELECT
              id,
              proceso_id,
              nombre,
              unidad_medida
            FROM ensayos_laboratorio
            WHERE activo = 1
            ORDER BY nombre ASC
            `
        );
        const ensayosLaboratorio = ensayosLaboratorioResult.recordset;

        const contextos = await Promise.all(
            rows.map(async (contexto) => {
                const parametrosVisualesResult = await poolConn.request()
                    .input('processId', sql.Int, contexto.processId)
                    .query(
                        `
          SELECT
            id,
            proceso_id,
            nombre,
            criticidad
          FROM parametros_control_visual
          WHERE activo = 1
            AND proceso_id = @processId
          ORDER BY
            CASE criticidad WHEN 'critico' THEN 1 WHEN 'mayor' THEN 2 WHEN 'menor' THEN 3 ELSE 4 END,
            nombre ASC
          `
                    );
                const parametrosVisuales = parametrosVisualesResult.recordset;

                const origenesProblemaResult = await poolConn.request()
                    .input('processId', sql.Int, contexto.processId)
                    .query(
                        `
                    SELECT
                      id,
                      proceso_id,
                      nombre
                    FROM origenes_problema
                    WHERE activo = 1
                      AND proceso_id = @processId
                    ORDER BY nombre ASC
                    `
                    );
                const origenesProblema = origenesProblemaResult.recordset;

                const operadoresMaquinaResult = await poolConn.request()
                    .input('processId', sql.Int, contexto.processId)
                    .query(
                        `
                    SELECT
                      id,
                      proceso_id,
                      nombre
                    FROM operadores_maquina
                    WHERE activo = 1
                      AND proceso_id = @processId
                    ORDER BY nombre ASC
                    `
                    );
                const operadoresMaquina = operadoresMaquinaResult.recordset;

                return {
                    ...contexto,
                    parametrosVisuales,
                    origenesProblema,
                    operadoresMaquina,
                    tiposOnda: contexto.processId === 1 ? tiposOnda : [],
                    materiales,
                    ensayosLaboratorio,
                };
            })
        );

        res.json({
            ok: true,
            data: contextos,
        });
    } catch (error) {
        console.error('Error contexto QR:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener contexto por QR',
            error: error.message,
        });
    }
};
const crearRegistroControl = async (req, res) => {
    const poolConn = await getCalidadSqlServerPool();
    const transaction = new sql.Transaction(poolConn);
    let clientUuidEnvio = null;

    try {
        console.log('==========================');
        console.log('REQ.FILE:', req.file);
        console.log('REQ.BODY:', req.body);
        console.log('==========================');
        let body = req.body;

        if (body.payload) {
            body = JSON.parse(body.payload);
        }

        const {
            usuarioId,
            procesoId,
            maquinaId,
            formularioId,
            area,
            np,
            cliente,
            codigoProducto,
            descripcionProducto,
            tipoOndaId,
            mermaInsumosDesponcheBobinas,
            mermaProcesoMonotapas,
            turno,
            resultadoVisual,
            observacion,
            requiereEnsayoLaboratorio,
            requiereMerma,
            tipoMerma,
            cantidadMerma,
            fallasVisuales,
            ensayosLaboratorio,
            bobinas,
            origenId,
            operadorMaquinaId,
            clientId,
            humedadBobina,
            humedadLinerIzquierda,
            humedadLinerCentro,
            humedadLinerDerecha,
            humedadOndaIzquierda,
            humedadOndaCentro,
            humedadOndaDerecha,
        } = body;

        if (!usuarioId || !procesoId || !maquinaId || !turno || !resultadoVisual) {
            borrarArchivos(req);
            return res.status(400).json({
                ok: false,
                message: 'Faltan datos obligatorios del control',
            });
        }

        const estadoIdPorResultado = {
            'Cumple': 1,
            'No Cumple': 3,
            'No Aplica': 2,
        };

        const estadoId = estadoIdPorResultado[resultadoVisual];

        if (!estadoId) {
            borrarArchivos(req);
            return res.status(400).json({
                ok: false,
                message: 'Resultado visual inválido',
            });
        }
        const esCorrugado = Number(procesoId) === 1;
        const esProduccion = area === 'PRODUCCION INNPACK';
        const mostrarHumedad = esCorrugado && esProduccion;

        const tipoOndaIdFinal = esCorrugado ? tipoOndaId || null : null;
        const mermaInsumosFinal = esCorrugado ? mermaInsumosDesponcheBobinas || null : null;
        const mermaProcesoFinal = esCorrugado ? mermaProcesoMonotapas || null : null;

        const humedadBobinaFinal = mostrarHumedad ? humedadBobina || null : null;
        const humedadLinerIzquierdaFinal = mostrarHumedad ? humedadLinerIzquierda || null : null;
        const humedadLinerCentroFinal = mostrarHumedad ? humedadLinerCentro || null : null;
        const humedadLinerDerechaFinal = mostrarHumedad ? humedadLinerDerecha || null : null;
        const humedadOndaIzquierdaFinal = mostrarHumedad ? humedadOndaIzquierda || null : null;
        const humedadOndaCentroFinal = mostrarHumedad ? humedadOndaCentro || null : null;
        const humedadOndaDerechaFinal = mostrarHumedad ? humedadOndaDerecha || null : null;

        // Reintento del mismo envío (la app reenvía el mismo clientId): no se duplica el registro.
        const clientUuid = normalizarClientId(clientId);
        clientUuidEnvio = clientUuid;
        const registroExistente = async () => {
            if (!clientUuid) return null;
            const r = await poolConn.request()
                .input('clientUuid', sql.NVarChar(36), clientUuid)
                .query('SELECT id FROM registros_control WHERE client_uuid = @clientUuid');
            return r.recordset.length > 0 ? r.recordset[0].id : null;
        };
        const respuestaDuplicado = (registroId) => {
            borrarArchivos(req);
            return res.status(200).json({
                ok: true,
                duplicado: true,
                message: 'Control ya registrado',
                data: { registroId, estadoId },
            });
        };
        const idPrevio = await registroExistente();
        if (idPrevio) return respuestaDuplicado(idPrevio);

        let operadorMaquinaIdFinal = null;
        if (operadorMaquinaId) {
            const operadorResult = await poolConn.request()
                .input('operadorMaquinaId', sql.Int, operadorMaquinaId)
                .input('procesoId', sql.Int, procesoId)
                .query(
                    `
                SELECT id
                FROM operadores_maquina
                WHERE id = @operadorMaquinaId
                  AND proceso_id = @procesoId
                `
                );

            // Campo opcional: si no corresponde al proceso se guarda sin operador (no se rechaza la
            // inspección; un registro offline rechazado bloquearía la cola de sincronización).
            if (operadorResult.recordset.length === 0) {
                console.warn(
                    `operadorMaquinaId ${operadorMaquinaId} no corresponde al proceso ${procesoId}; se guarda sin operador`
                );
            } else {
                operadorMaquinaIdFinal = operadorMaquinaId;
            }
        }

        await transaction.begin();

        const registroResult = await new sql.Request(transaction)
            .input('usuarioId', sql.Int, usuarioId)
            .input('procesoId', sql.Int, procesoId)
            .input('maquinaId', sql.Int, maquinaId)
            .input('formularioId', sql.Int, formularioId || null)
            .input('area', sql.NVarChar(20), area || null)
            .input('np', sql.NVarChar(50), np || null)
            .input('cliente', sql.NVarChar(255), cliente || null)
            .input('codigoProducto', sql.NVarChar(100), codigoProducto || null)
            .input('descripcionProducto', sql.NVarChar(255), descripcionProducto || null)
            .input('tipoOndaId', sql.Int, tipoOndaIdFinal)
            .input('mermaInsumos', sql.Decimal(10, 2), mermaInsumosFinal)
            .input('mermaProceso', sql.Decimal(10, 2), mermaProcesoFinal)
            .input('turno', sql.NVarChar(1), turno)
            .input('estadoId', sql.Int, estadoId)
            .input('observacion', sql.NVarChar(120), observacion || null)
            .input('requiereEnsayoLaboratorio', sql.Bit, requiereEnsayoLaboratorio ? 1 : 0)
            .input('requiereMerma', sql.Bit, requiereMerma ? 1 : 0)
            .input('tipoMerma', sql.NVarChar(150), tipoMerma || null)
            .input('cantidadMerma', sql.Decimal(10, 2), cantidadMerma || null)
            .input('origenId', sql.Int, origenId || null)
            .input('operadorMaquinaId', sql.Int, operadorMaquinaIdFinal)
            .input('clientUuid', sql.NVarChar(36), clientUuid)
            .input('humedadBobina', sql.NVarChar(50), humedadBobinaFinal)
            .input('humedadLinerIzquierda', sql.NVarChar(50), humedadLinerIzquierdaFinal)
            .input('humedadLinerCentro', sql.NVarChar(50), humedadLinerCentroFinal)
            .input('humedadLinerDerecha', sql.NVarChar(50), humedadLinerDerechaFinal)
            .input('humedadOndaIzquierda', sql.NVarChar(50), humedadOndaIzquierdaFinal)
            .input('humedadOndaCentro', sql.NVarChar(50), humedadOndaCentroFinal)
            .input('humedadOndaDerecha', sql.NVarChar(50), humedadOndaDerechaFinal)
            .query(
                `
            INSERT INTO registros_control
            (
              usuario_id,
              proceso_id,
              maquina_id,
              formulario_id,
              area,
              np,
              cliente,
              codigo_producto,
              descripcion_producto,
              tipo_onda_id,
              merma_insumos_desponche_bobinas,
              merma_proceso_monotapas,
              turno,
              estado_id,
              observacion,
              requiere_ensayo_laboratorio,
              requiere_merma,
              tipo_merma,
              cantidad_merma,
              origen_id,
              operador_maquina_id,
              client_uuid,
              humedad_bobina,
              humedad_liner_izquierda,
              humedad_liner_centro,
              humedad_liner_derecha,
              humedad_onda_izquierda,
              humedad_onda_centro,
              humedad_onda_derecha,
              fecha_registro,
              hora_registro
            )
            OUTPUT INSERTED.id
            VALUES (@usuarioId, @procesoId, @maquinaId, @formularioId, @area, @np, @cliente, @codigoProducto,
              @descripcionProducto, @tipoOndaId, @mermaInsumos, @mermaProceso, @turno, @estadoId, @observacion,
              @requiereEnsayoLaboratorio, @requiereMerma, @tipoMerma, @cantidadMerma, @origenId, @operadorMaquinaId, @clientUuid, @humedadBobina,
              @humedadLinerIzquierda, @humedadLinerCentro, @humedadLinerDerecha, @humedadOndaIzquierda,
              @humedadOndaCentro, @humedadOndaDerecha, CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))
            `
            );

        const registroId = registroResult.recordset[0].id;
        if (req.file) {
            const rutaRelativa = `/uploads/control/${req.file.filename}`;

            await new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('nombreOriginal', sql.NVarChar(255), req.file.originalname)
                .input('nombreArchivo', sql.NVarChar(255), req.file.filename)
                .input('rutaArchivo', sql.NVarChar(500), rutaRelativa)
                .input('mimeType', sql.NVarChar(100), req.file.mimetype)
                .input('tamanoBytes', sql.Int, req.file.size)
                .query(
                    `
                INSERT INTO registro_adjuntos
                (
                  registro_id,
                  nombre_original,
                  nombre_archivo,
                  ruta_archivo,
                  mime_type,
                  tamano_bytes
                )
                VALUES (@registroId, @nombreOriginal, @nombreArchivo, @rutaArchivo, @mimeType, @tamanoBytes)
                `
                );
        }

        if (Array.isArray(fallasVisuales) && fallasVisuales.length > 0) {
            for (const falla of fallasVisuales) {
                await new sql.Request(transaction)
                    .input('registroId', sql.Int, registroId)
                    .input('parametroId', sql.Int, falla.parametroId)
                    .input('accionId', sql.Int, falla.accionId || null)
                    .input('observacion', sql.NVarChar(120), falla.observacion || null)
                    .query(
                        `
            INSERT INTO registro_fallas_visuales
            (
              registro_id,
              parametro_id,
              accion_id,
              observacion
            )
            VALUES (@registroId, @parametroId, @accionId, @observacion)
            `
                    );
            }
        }

        if (Array.isArray(ensayosLaboratorio) && ensayosLaboratorio.length > 0) {
            for (const ensayo of ensayosLaboratorio) {
                await new sql.Request(transaction)
                    .input('registroId', sql.Int, registroId)
                    .input('ensayoId', sql.Int, ensayo.ensayoId)
                    .input('materialId', sql.Int, ensayo.materialId || null)
                    .input('valor', sql.Decimal(10, 2), null)
                    .input('observacion', sql.NVarChar(120), ensayo.observacion || null)
                    .query(
                        `
                    INSERT INTO registro_ensayos
                    (
                      registro_id,
                      ensayo_id,
                      material_id,
                      valor,
                      observacion
                    )
                    VALUES (@registroId, @ensayoId, @materialId, @valor, @observacion)
                    `
                    );
            }
        }

        if (esCorrugado && Array.isArray(bobinas) && bobinas.length > 0) {
            for (const bobina of bobinas) {
                if (!bobina || !bobina.lote) {
                    continue;
                }

                await new sql.Request(transaction)
                    .input('registroId', sql.Int, registroId)
                    .input('tipo', sql.NVarChar(5), bobina.tipo || null)
                    .input('lote', sql.NVarChar(100), bobina.lote)
                    .input('docnum', sql.NVarChar(50), bobina.docnum || null)
                    .input('pesoTarjaKg', sql.Decimal(10, 2), bobina.pesoTarjaKg || null)
                    .input('itemCode', sql.NVarChar(50), bobina.itemCode || null)
                    .input('itemName', sql.NVarChar(255), bobina.itemName || null)
                    .input('gramaje', sql.NVarChar(50), bobina.gramaje || null)
                    .input('medida', sql.NVarChar(50), bobina.medida || null)
                    .input('ubicacionBin', sql.NVarChar(100), bobina.ubicacionBin || null)
                    .input('observacion', sql.NVarChar(120), bobina.observacion || null)
                    .input('escaneadoEn', sql.DateTime2, bobina.escaneadoEn ? new Date(bobina.escaneadoEn) : new Date())
                    .query(
                        `
                    INSERT INTO registro_control_bobinas
                    (
                      registro_id,
                      tipo,
                      lote,
                      docnum,
                      peso_tarja_kg,
                      item_code,
                      item_name,
                      gramaje,
                      medida,
                      ubicacion_bin,
                      observacion,
                      escaneado_en
                    )
                    VALUES (@registroId, @tipo, @lote, @docnum, @pesoTarjaKg, @itemCode, @itemName, @gramaje,
                      @medida, @ubicacionBin, @observacion, @escaneadoEn)
                    `
                    );
            }
        }

        await transaction.commit();

        res.status(201).json({
            ok: true,
            message: 'Control registrado correctamente',
            data: {
                registroId,
                estadoId,
            },
        });
    } catch (error) {
        try {
            await transaction.rollback();
        } catch (_) { }

        borrarArchivos(req);

        // Dos reintentos simultáneos con el mismo clientId: el índice único deja pasar solo uno.
        if ((error.number === 2601 || error.number === 2627) && clientUuidEnvio) {
            try {
                const previo = await poolConn.request()
                    .input('clientUuid', sql.NVarChar(36), clientUuidEnvio)
                    .query('SELECT id FROM registros_control WHERE client_uuid = @clientUuid');
                if (previo.recordset.length > 0) {
                    return res.status(200).json({
                        ok: true,
                        duplicado: true,
                        message: 'Control ya registrado',
                        data: { registroId: previo.recordset[0].id },
                    });
                }
            } catch (_) { }
        }

        console.error('==========================');
        console.error('ERROR COMPLETO');
        console.error(error);
        console.error('==========================');
        res.status(500).json({
            ok: false,
            message: 'Error al guardar control',
            error: error.message,
        });
    }
};

module.exports = {
    getContextoPorQr,
    crearRegistroControl,
};
