const { getSapSqlServerPool, sql } = require('../config/sqlServerPoolSap');
const pool = require('../config/database');

const GRAMAJE_REGEX = /(\d{2,4})\s*GRS?\b/i;
const MEDIDA_REGEX = /(\d+(?:[.,]\d+)?\s*[Xx]\s*\d+(?:[.,]\d+)?|\d+(?:[.,]\d+)?\s*CM)\b/;

const parseItemName = (itemName) => {
    if (!itemName) {
        return { gramaje: null, medida: null };
    }

    const gramajeMatch = itemName.match(GRAMAJE_REGEX);
    const medidaMatch = itemName.match(MEDIDA_REGEX);

    return {
        gramaje: gramajeMatch ? gramajeMatch[1] : null,
        medida: medidaMatch ? medidaMatch[1].trim() : null,
    };
};

const SAP_QUERY = `
SELECT TOP 1
    T0.ItemCode AS item_code,
    T1.ItemName AS item_name,
    T1.InvntryUom AS uom,
    T2.DistNumber AS lote,
    SUM(T0.Quantity) AS quantity,
    BIN_DATA.ubicacion_bin AS ubicacion_bin
FROM OBTQ T0
INNER JOIN OBTN T2
    ON T0.MdAbsEntry = T2.AbsEntry
INNER JOIN OITM T1
    ON T0.ItemCode = T1.ItemCode

OUTER APPLY (
    SELECT TOP 1
        V.BinCode AS ubicacion_bin
    FROM B1_SnBTransRptFirstBinView V
    WHERE V.SnBMDAbs = T2.AbsEntry
    ORDER BY V.ITLEntry DESC
) BIN_DATA

WHERE
    T2.DistNumber = @lote
GROUP BY
    T0.ItemCode,
    T1.ItemName,
    T1.InvntryUom,
    T2.DistNumber,
    BIN_DATA.ubicacion_bin
ORDER BY
    SUM(T0.Quantity) DESC
`;

const obtenerBobinaPorLote = async (req, res) => {
    const { lote } = req.params;
    const loteLimpio = (lote || '').trim();

    if (!loteLimpio) {
        return res.status(400).json({ ok: false, message: 'Lote inválido' });
    }

    try {
        const pool = await getSapSqlServerPool();

        const result = await pool.request()
            .input('lote', sql.NVarChar, loteLimpio)
            .query(SAP_QUERY);

        const row = result.recordset[0];

        if (!row) {
            return res.status(404).json({
                ok: false,
                message: 'LOTE_NO_ENCONTRADO_EN_SAP',
                lote: loteLimpio,
            });
        }

        const { gramaje, medida } = parseItemName(row.item_name);

        res.json({
            ok: true,
            data: {
                lote: row.lote,
                itemCode: row.item_code || null,
                itemName: row.item_name || null,
                uom: row.uom || null,
                quantity: row.quantity !== null ? Number(row.quantity) : null,
                ubicacionBin: row.ubicacion_bin || null,
                gramaje,
                medida,
            },
        });
    } catch (error) {
        console.error('Error consultando bobina en SAP:', error.message);

        res.status(503).json({
            ok: false,
            message: 'No se pudo consultar SAP para resolver la bobina',
            error: error.message,
        });
    }
};

const obtenerBobinasPorNp = async (req, res) => {
    const { np } = req.params;

    try {
        const [rows] = await pool.query(
            `
            SELECT
              b.id,
              b.registro_id,
              b.tipo,
              b.lote,
              b.docnum,
              b.peso_tarja_kg,
              b.item_code,
              b.item_name,
              b.gramaje,
              b.medida,
              b.ubicacion_bin,
              b.observacion,
              b.escaneado_en,
              rc.np,
              rc.maquina_id,
              rc.fecha_registro,
              rc.hora_registro
            FROM registro_control_bobinas b
            INNER JOIN registros_control rc ON rc.id = b.registro_id
            WHERE rc.np = ? AND rc.eliminado = 0
            ORDER BY b.tipo ASC, b.escaneado_en ASC
            `,
            [np]
        );

        res.json({ ok: true, data: rows });
    } catch (error) {
        console.error('Error consultando bobinas por NP:', error.message);

        res.status(500).json({
            ok: false,
            message: 'Error al obtener bobinas por NP',
            error: error.message,
        });
    }
};

module.exports = {
    obtenerBobinaPorLote,
    obtenerBobinasPorNp,
};
