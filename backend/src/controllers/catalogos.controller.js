const { getCalidadSqlServerPool, sql } = require('../config/calidadSqlServerPool');

const getUsuarios = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const result = await pool.request().query(`
      SELECT
        id,
        codigo_usuario,
        nombre_completo
      FROM usuarios
      WHERE activo = 1
      ORDER BY nombre_completo ASC
    `);

        res.json({
            ok: true,
            data: result.recordset,
        });
    } catch (error) {
        console.error('Error usuarios:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener usuarios',
            error: error.message,
        });
    }
};

const getProcesos = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const result = await pool.request().query(`
      SELECT
        id,
        nombre
      FROM procesos
      WHERE activo = 1
      ORDER BY nombre ASC
    `);

        res.json({
            ok: true,
            data: result.recordset,
        });
    } catch (error) {
        console.error('Error procesos:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener procesos',
            error: error.message,
        });
    }
};

const getMaquinas = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const result = await pool.request().query(`
      SELECT
        m.id,
        m.nombre,
        m.codigo_qr,
        m.proceso_id,
        p.nombre AS proceso_nombre
      FROM maquinas m
      INNER JOIN procesos p ON p.id = m.proceso_id
      WHERE m.activo = 1
      ORDER BY p.nombre ASC, m.nombre ASC
    `);

        res.json({
            ok: true,
            data: result.recordset,
        });
    } catch (error) {
        console.error('Error maquinas:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener maquinas',
            error: error.message,
        });
    }
};
const getParametrosVisuales = async (req, res) => {
    try {
        const { procesoId } = req.params;

        const pool = await getCalidadSqlServerPool();
        const result = await pool.request()
            .input('procesoId', sql.Int, procesoId)
            .query(
                `
        SELECT
          id,
          proceso_id,
          nombre,
          criticidad
        FROM parametros_control_visual
        WHERE activo = 1
          AND proceso_id = @procesoId
        ORDER BY
          CASE criticidad WHEN 'critico' THEN 1 WHEN 'mayor' THEN 2 WHEN 'menor' THEN 3 ELSE 4 END,
          nombre ASC
        `
            );

        res.json({
            ok: true,
            data: result.recordset,
        });
    } catch (error) {
        console.error('Error parametros visuales:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener parámetros visuales',
            error: error.message,
        });
    }
};
const getOrigenesProblema = async (req, res) => {
    try {
        const { procesoId } = req.params;

        const pool = await getCalidadSqlServerPool();
        const result = await pool.request()
            .input('procesoId', sql.Int, procesoId)
            .query(
                `
        SELECT
          id,
          proceso_id,
          nombre
        FROM origenes_problema
        WHERE activo = 1
          AND proceso_id = @procesoId
        ORDER BY nombre ASC
        `
            );

        res.json({
            ok: true,
            data: result.recordset,
        });
    } catch (error) {
        console.error('Error origenes problema:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener orígenes del problema',
            error: error.message,
        });
    }
};
const getCatalogoOffline = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();

        const usuariosResult = await pool.request().query(`
      SELECT
        id,
        codigo_usuario,
        nombre_completo
      FROM usuarios
      WHERE activo = 1
      ORDER BY nombre_completo ASC
    `);

        const contextosResult = await pool.request().query(`
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
      WHERE m.activo = 1
      ORDER BY p.nombre ASC, m.nombre ASC
    `);

        const parametrosVisualesResult = await pool.request().query(`
      SELECT
        id,
        proceso_id,
        nombre,
        criticidad
      FROM parametros_control_visual
      WHERE activo = 1
      ORDER BY
        proceso_id ASC,
        CASE criticidad WHEN 'critico' THEN 1 WHEN 'mayor' THEN 2 WHEN 'menor' THEN 3 ELSE 4 END,
        nombre ASC
    `);
        const tiposOndaResult = await pool.request().query(`
  SELECT
    id,
    nombre
  FROM tipos_onda
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const materialesResult = await pool.request().query(`
  SELECT
    id,
    nombre
  FROM materiales
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const ensayosLaboratorioResult = await pool.request().query(`
  SELECT
    id,
    proceso_id,
    nombre,
    unidad_medida
  FROM ensayos_laboratorio
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const origenesProblemaResult = await pool.request().query(`
  SELECT
    id,
    proceso_id,
    nombre
  FROM origenes_problema
  WHERE activo = 1
  ORDER BY proceso_id ASC, nombre ASC
`);

        const usuarios = usuariosResult.recordset;
        const contextos = contextosResult.recordset;
        const parametrosVisuales = parametrosVisualesResult.recordset;
        const tiposOnda = tiposOndaResult.recordset;
        const materiales = materialesResult.recordset;
        const ensayosLaboratorio = ensayosLaboratorioResult.recordset;
        const origenesProblema = origenesProblemaResult.recordset;

        const qrContexts = contextos.map((contexto) => ({
            ...contexto,

            parametrosVisuales: parametrosVisuales.filter(
                (parametro) => parametro.proceso_id === contexto.processId
            ),

            origenesProblema: origenesProblema.filter(
                (origen) => origen.proceso_id === contexto.processId
            ),

            tiposOnda:
                contexto.processId === 1
                    ? tiposOnda
                    : [],

            materiales,

            ensayosLaboratorio,
        }));

        res.json({
            ok: true,
            data: {
                usuarios,
                qrContexts,
            },
        });

    } catch (error) {

        console.error('Error catalogo offline:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener catálogo offline',
            error: error.message,
        });

    }
};

module.exports = {
    getUsuarios,
    getProcesos,
    getMaquinas,
    getParametrosVisuales,
    getOrigenesProblema,
    getCatalogoOffline,
};
