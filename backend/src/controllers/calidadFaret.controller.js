const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');
const { borrarArchivos, normalizarClientId } = require('../utils/uploads');
const { ErrorValidacion, resolverDefectos, obtenerCatalogo, esErrorTriggerEvento } = require('../utils/eventosCalidadFaret');
const { auditoriaDisponible, resumenEdicionSql } = require('../utils/edicionInspecciones');

const crearRegistroCalidadFaret = async (req, res) => {
    const poolConn = await getCalidadSqlServerPool();
    const transaction = new sql.Transaction(poolConn);
    let clientUuidEnvio = null;

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
            clientId,
        } = body;

        if (!nvFaret || !areaControl || !operador || !maquina) {
            borrarArchivos(req);
            return res.status(400).json({
                ok: false,
                message: 'Faltan datos obligatorios del formulario',
            });
        }

        // Reintento del mismo envío (la app reenvía el mismo clientId): no se duplica el registro.
        const clientUuid = normalizarClientId(clientId);
        clientUuidEnvio = clientUuid;
        if (clientUuid) {
            const previo = await poolConn.request()
                .input('clientUuid', sql.NVarChar(36), clientUuid)
                .query('SELECT id FROM registros_calidad_faret WHERE client_uuid = @clientUuid');
            if (previo.recordset.length > 0) {
                borrarArchivos(req);
                return res.status(200).json({
                    ok: true,
                    duplicado: true,
                    message: 'Registro de calidad Faret ya guardado',
                    data: { registroId: previo.recordset[0].id },
                });
            }
        }

        // Defectos: texto legado y/o {idEvento}. Texto y criticidad salen del catálogo en SQL Server (nunca del cliente).
        const defectosResueltos = presentaDefectos ? await resolverDefectos(poolConn, defectos, areaDefecto) : [];

        await transaction.begin();

        const registroResult = await new sql.Request(transaction)
            .input('nvFaret', sql.NVarChar(100), nvFaret)
            .input('nvVoBoAprobado', sql.Bit, nvVoBoAprobado ? 1 : 0)
            .input('nPliego', sql.NVarChar(100), nPliego || null)
            .input('nPasada', sql.NVarChar(100), nPasada || null)
            .input('nItem', sql.NVarChar(100), nItem || null)
            .input('pliegoControlN', sql.NVarChar(100), pliegoControlN || null)
            .input('observaciones', sql.NVarChar(sql.MAX), observaciones || null)
            .input('areaControl', sql.NVarChar(50), areaControl)
            .input('operador', sql.NVarChar(150), operador)
            .input('operadorOtro', sql.NVarChar(150), operadorOtro || null)
            .input('operadorRegistro', sql.NVarChar(150), operadorRegistro || null)
            .input('maquina', sql.NVarChar(100), maquina)
            .input('presentaDefectos', sql.Bit, presentaDefectos ? 1 : 0)
            .input('areaDefecto', sql.NVarChar(50), presentaDefectos ? areaDefecto || null : null)
            .input('tipoFolia', sql.NVarChar(150), presentaDefectos ? tipoFolia || null : null)
            .input('accionCorrectiva', sql.NVarChar(sql.MAX), presentaDefectos ? accionCorrectiva || null : null)
            .input('clientUuid', sql.NVarChar(36), clientUuid)
            .query(
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
              client_uuid,
              fecha_registro,
              hora_registro
            )
            OUTPUT INSERTED.id
            VALUES (@nvFaret, @nvVoBoAprobado, @nPliego, @nPasada, @nItem, @pliegoControlN, @observaciones,
              @areaControl, @operador, @operadorOtro, @operadorRegistro, @maquina, @presentaDefectos,
              @areaDefecto, @tipoFolia, @accionCorrectiva, @clientUuid, CAST(GETDATE() AS DATE), CAST(GETDATE() AS TIME(0)))
            `
            );

        const registroId = registroResult.recordset[0].id;

        for (const defecto of defectosResueltos) {
            const peticion = new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('defecto', sql.NVarChar(150), defecto.texto);
            if (defecto.idEvento) {
                await peticion
                    .input('idEvento', sql.NVarChar(10), defecto.idEvento)
                    .input('criticidad', sql.NVarChar(10), defecto.criticidad)
                    .query(
                        `
                    INSERT INTO registro_calidad_faret_defectos
                    (registro_id, defecto, id_evento, criticidad)
                    VALUES (@registroId, @defecto, @idEvento, @criticidad)
                    `
                    );
            } else {
                // Cliente sin catálogo: mismo INSERT de siempre (funciona también si la 010 se revirtiera).
                await peticion.query(
                    `
                    INSERT INTO registro_calidad_faret_defectos
                    (registro_id, defecto)
                    VALUES (@registroId, @defecto)
                    `
                );
            }
        }

        if (operadorRegistro && String(operadorRegistro).trim()) {
            try {
                await new sql.Request(transaction)
                    .input('nombre', sql.NVarChar(150), String(operadorRegistro).trim())
                    .query(
                        `
                        IF NOT EXISTS (SELECT 1 FROM calidad_faret_operadores WHERE nombre = @nombre)
                        BEGIN
                            INSERT INTO calidad_faret_operadores (nombre) VALUES (@nombre)
                        END
                        `
                    );
            } catch (errorOperador) {
                // UQ_calidad_faret_operadores_nombre (mismo criterio que INSERT IGNORE en MySQL):
                // una carrera entre 2 registros con el mismo operador nuevo es la unica forma de
                // llegar aca (el IF NOT EXISTS de arriba ya cubre el caso normal) -- se ignora,
                // igual que hacia INSERT IGNORE.
                if (errorOperador.number !== 2627 && errorOperador.number !== 2601) {
                    throw errorOperador;
                }
            }
        }

        const archivos = Array.isArray(req.files) ? req.files : [];

        for (const archivo of archivos) {
            const rutaRelativa = `/uploads/calidad_faret/${archivo.filename}`;

            await new sql.Request(transaction)
                .input('registroId', sql.Int, registroId)
                .input('nombreOriginal', sql.NVarChar(255), archivo.originalname)
                .input('nombreArchivo', sql.NVarChar(255), archivo.filename)
                .input('rutaArchivo', sql.NVarChar(255), rutaRelativa)
                .input('mimeType', sql.NVarChar(100), archivo.mimetype)
                .input('tamanoBytes', sql.Int, archivo.size)
                .query(
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
                VALUES (@registroId, @nombreOriginal, @nombreArchivo, @rutaArchivo, @mimeType, @tamanoBytes)
                `
                );
        }

        await transaction.commit();

        res.status(201).json({
            ok: true,
            message: 'Registro de calidad Faret guardado correctamente',
            data: {
                registroId,
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
                    .query('SELECT id FROM registros_calidad_faret WHERE client_uuid = @clientUuid');
                if (previo.recordset.length > 0) {
                    return res.status(200).json({
                        ok: true,
                        duplicado: true,
                        message: 'Registro de calidad Faret ya guardado',
                        data: { registroId: previo.recordset[0].id },
                    });
                }
            } catch (_) { }
        }

        if (error instanceof ErrorValidacion) {
            return res.status(error.status).json({ ok: false, message: error.message });
        }
        if (esErrorTriggerEvento(error)) {
            // El evento dejó de estar operable (o no corresponde al área) entre la validación y el INSERT.
            return res.status(400).json({ ok: false, message: 'El evento de calidad ya no está disponible; actualice el catálogo' });
        }

        console.error('Error al guardar registro calidad Faret:', error);

        res.status(500).json({
            ok: false,
            message: 'Error al guardar registro',
            error: error.message,
        });
    }
};

// Catálogo público y de solo lectura (sin datos de inspecciones ni de personas): áreas activas y solo los eventos operables.
const obtenerCatalogoEventosCalidadFaret = async (req, res) => {
    try {
        const catalogo = await obtenerCatalogo(await getCalidadSqlServerPool());
        const etag = `"${catalogo.version}"`;
        res.set('ETag', etag);
        res.set('Cache-Control', 'no-cache');   // se puede guardar, pero siempre se revalida con If-None-Match (304)
        if (req.headers['if-none-match'] === etag) return res.status(304).end();
        res.json({ ok: true, data: catalogo });
    } catch (error) {
        console.error('Error al consultar el catálogo de eventos Faret:', error.message);
        res.status(503).json({ ok: false, message: 'Catálogo de eventos no disponible' });
    }
};

const buildFiltros = (query) => {
    const { fechaDesde, fechaHasta, areaControl, operador, maquina, presentaDefectos, nvFaret, criticidad } = query;

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

    if (areaControl) {
        condiciones.push('r.area_control = @areaControl');
        inputs.push({ name: 'areaControl', type: sql.NVarChar(50), value: areaControl });
    }

    if (nvFaret) {
        condiciones.push('r.nv_faret LIKE @nvFaret');
        inputs.push({ name: 'nvFaret', type: sql.NVarChar(100), value: `%${nvFaret}%` });
    }

    if (operador) {
        condiciones.push('r.operador LIKE @operador');
        inputs.push({ name: 'operador', type: sql.NVarChar(150), value: `%${operador}%` });
    }

    if (maquina) {
        condiciones.push('r.maquina LIKE @maquina');
        inputs.push({ name: 'maquina', type: sql.NVarChar(100), value: `%${maquina}%` });
    }

    if (presentaDefectos === 'true' || presentaDefectos === '1') {
        condiciones.push('r.presenta_defectos = 1');
    } else if (presentaDefectos === 'false' || presentaDefectos === '0') {
        condiciones.push('r.presenta_defectos = 0');
    }

    // Registros con al menos un defecto de esa criticidad (Critico / Mayor / Menor; los históricos sin criticidad no coinciden).
    if (['Critico', 'Mayor', 'Menor'].includes(criticidad)) {
        condiciones.push('EXISTS (SELECT 1 FROM registro_calidad_faret_defectos dc WHERE dc.registro_id = r.id AND dc.criticidad = @criticidad)');
        inputs.push({ name: 'criticidad', type: sql.NVarChar(10), value: criticidad });
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

const listarRegistrosCalidadFaret = async (req, res) => {
    try {
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const pageSize = Math.min(200, Math.max(1, parseInt(req.query.pageSize, 10) || 50));
        const offset = (page - 1) * pageSize;

        const { whereSql, inputs } = buildFiltros(req.query);
        const poolConn = await getCalidadSqlServerPool();

        const countResult = await aplicarInputs(poolConn.request(), inputs).query(
            `SELECT COUNT(*) AS total FROM registros_calidad_faret r ${whereSql}`
        );

        const edicionSql = (await auditoriaDisponible(poolConn)) ? resumenEdicionSql('CALIDAD') : '';
        const rowsResult = await aplicarInputs(poolConn.request(), inputs)
            .input('pageSize', sql.Int, pageSize)
            .input('offset', sql.Int, offset)
            .query(
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
                SELECT STUFF((
                  SELECT ', ' + d2.defecto
                  FROM registro_calidad_faret_defectos d2
                  WHERE d2.registro_id = r.id
                  FOR XML PATH(''), TYPE
                ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
              ) AS defectos,
              (
                SELECT d3.id_evento AS idEvento, d3.defecto, d3.criticidad
                FROM registro_calidad_faret_defectos d3
                WHERE d3.registro_id = r.id
                ORDER BY d3.id_evento, d3.defecto
                FOR JSON PATH
              ) AS defectosDetalle,
              (
                SELECT CASE MAX(CASE d4.criticidad WHEN N'Critico' THEN 3 WHEN N'Mayor' THEN 2 WHEN N'Menor' THEN 1 END)
                         WHEN 3 THEN N'Critico' WHEN 2 THEN N'Mayor' WHEN 1 THEN N'Menor' END
                FROM registro_calidad_faret_defectos d4
                WHERE d4.registro_id = r.id
              ) AS criticidadMax,
              (
                SELECT COUNT(*)
                FROM registro_calidad_faret_adjuntos a
                WHERE a.registro_id = r.id
              ) AS cantidadAdjuntos${edicionSql}
            FROM registros_calidad_faret r
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
        const { whereSql, inputs } = buildFiltros(req.query);
        const poolConn = await getCalidadSqlServerPool();

        const resumenResult = await aplicarInputs(poolConn.request(), inputs).query(
            `
            SELECT
              COUNT(*) AS inspecciones_periodo,
              SUM(CASE WHEN presenta_defectos = 1 THEN 1 ELSE 0 END) AS con_defectos,
              SUM(CASE WHEN presenta_defectos = 0 THEN 1 ELSE 0 END) AS sin_defectos
            FROM registros_calidad_faret r
            ${whereSql}
            `
        );
        const resumen = resumenResult.recordset[0];

        const hoyResult = await poolConn.request().query(`
            SELECT COUNT(*) AS inspecciones_hoy
            FROM registros_calidad_faret
            WHERE fecha_registro = CAST(GETDATE() AS DATE)
        `);
        const hoy = hoyResult.recordset[0];

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

        const poolConn = await getCalidadSqlServerPool();

        const maquinasResult = await poolConn.request().query(`
            SELECT
              maquina,
              area_control AS areaControl,
              COUNT(*) AS totalRegistros
            FROM registros_calidad_faret
            WHERE maquina IS NOT NULL AND maquina <> ''
            GROUP BY maquina, area_control
            ORDER BY area_control, maquina
        `);
        const maquinas = maquinasResult.recordset;

        const data = {
            totalMaquinas: maquinas.length,
            maquinas,
            registrosMaquinaSeleccionada: 0,
            conDefectosMaquinaSeleccionada: 0,
            registros: [],
        };

        if (maquina) {
            const statsResult = await poolConn.request()
                .input('maquina', sql.NVarChar(100), maquina)
                .query(
                    `
                SELECT
                  COUNT(*) AS totalRegistros,
                  SUM(CASE WHEN presenta_defectos = 1 THEN 1 ELSE 0 END) AS conDefectos
                FROM registros_calidad_faret
                WHERE maquina = @maquina
                `
                );
            const stats = statsResult.recordset[0];

            data.registrosMaquinaSeleccionada = Number(stats.totalRegistros) || 0;
            data.conDefectosMaquinaSeleccionada = Number(stats.conDefectos) || 0;

            const registrosResult = await poolConn.request()
                .input('maquina', sql.NVarChar(100), maquina)
                .query(
                    `
                SELECT TOP 100
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
                    SELECT STUFF((
                      SELECT ', ' + d2.defecto
                      FROM registro_calidad_faret_defectos d2
                      WHERE d2.registro_id = r.id
                      FOR XML PATH(''), TYPE
                    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
                  ) AS defectos
                FROM registros_calidad_faret r
                WHERE r.maquina = @maquina
                ORDER BY r.fecha_registro DESC, r.hora_registro DESC
                `
                );

            data.registros = registrosResult.recordset;
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

        const poolConn = await getCalidadSqlServerPool();
        const adjuntosResult = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                `
            SELECT
              id,
              nombre_original AS nombreOriginal,
              ruta_archivo AS rutaArchivo,
              mime_type AS mimeType
            FROM registro_calidad_faret_adjuntos
            WHERE registro_id = @id
            ORDER BY id ASC
            `
            );

        res.json({ ok: true, data: adjuntosResult.recordset });
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

        const poolConn = await getCalidadSqlServerPool();
        const resultado = await poolConn.request()
            .input('id', sql.Int, id)
            .query(
                'UPDATE registros_calidad_faret SET eliminado = 1 WHERE id = @id AND eliminado = 0'
            );

        if (resultado.rowsAffected[0] === 0) {
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
    obtenerCatalogoEventosCalidadFaret,
    crearRegistroCalidadFaret,
    listarRegistrosCalidadFaret,
    obtenerResumenCalidadFaret,
    obtenerResumenMaquinasCalidadFaret,
    listarAdjuntosRegistroCalidadFaret,
    eliminarRegistroCalidadFaret,
};
