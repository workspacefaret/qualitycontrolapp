const pool = require('../config/database');

const getUsuarios = async (req, res) => {
    try {
        const [rows] = await pool.query(`
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
            data: rows,
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
        const [rows] = await pool.query(`
      SELECT
        id,
        nombre
      FROM procesos
      WHERE activo = 1
      ORDER BY nombre ASC
    `);

        res.json({
            ok: true,
            data: rows,
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
        const [rows] = await pool.query(`
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
            data: rows,
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

        const [rows] = await pool.query(
            `
        SELECT
          id,
          proceso_id,
          nombre,
          criticidad
        FROM parametros_control_visual
        WHERE activo = 1
          AND proceso_id = ?
        ORDER BY
          FIELD(criticidad, 'critico', 'mayor', 'menor'),
          nombre ASC
        `,
            [procesoId]
        );

        res.json({
            ok: true,
            data: rows,
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
const getCatalogoOffline = async (req, res) => {
    try {
        const [usuarios] = await pool.query(`
      SELECT
        id,
        codigo_usuario,
        nombre_completo
      FROM usuarios
      WHERE activo = 1
      ORDER BY nombre_completo ASC
    `);

        const [contextos] = await pool.query(`
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

        const [parametrosVisuales] = await pool.query(`
      SELECT
        id,
        proceso_id,
        nombre,
        criticidad
      FROM parametros_control_visual
      WHERE activo = 1
      ORDER BY
        proceso_id ASC,
        FIELD(criticidad, 'critico', 'mayor', 'menor'),
        nombre ASC
    `);
        const [tiposOnda] = await pool.query(`
  SELECT
    id,
    nombre
  FROM tipos_onda
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const [materiales] = await pool.query(`
  SELECT
    id,
    nombre
  FROM materiales
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const [ensayosLaboratorio] = await pool.query(`
  SELECT
    id,
    proceso_id,
    nombre,
    unidad_medida
  FROM ensayos_laboratorio
  WHERE activo = 1
  ORDER BY nombre ASC
`);

        const qrContexts = contextos.map((contexto) => ({
            ...contexto,

            parametrosVisuales: parametrosVisuales.filter(
                (parametro) => parametro.proceso_id === contexto.processId
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
    getCatalogoOffline,
};
