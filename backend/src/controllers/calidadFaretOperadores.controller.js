const { getCalidadSqlServerPool } = require('../config/calidadSqlServerPool');

const listarOperadoresCalidadFaret = async (req, res) => {
    try {
        const pool = await getCalidadSqlServerPool();
        const result = await pool.request().query(`
            SELECT nombre
            FROM calidad_faret_operadores
            ORDER BY nombre ASC
        `);

        res.json({
            ok: true,
            data: result.recordset.map((o) => o.nombre),
        });
    } catch (error) {
        console.error('Error al listar operadores calidad Faret:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al listar operadores',
            error: error.message,
        });
    }
};

module.exports = {
    listarOperadoresCalidadFaret,
};
