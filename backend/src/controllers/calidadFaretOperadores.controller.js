const pool = require('../config/database');

const listarOperadoresCalidadFaret = async (req, res) => {
    try {
        const [operadores] = await pool.query(`
            SELECT nombre
            FROM calidad_faret_operadores
            ORDER BY nombre ASC
        `);

        res.json({
            ok: true,
            data: operadores.map((o) => o.nombre),
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
