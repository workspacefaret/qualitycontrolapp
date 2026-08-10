const { getSqlServerPool, sql } = require('../config/sqlServerPool');

const obtenerOrdenFabricacion = async (req, res) => {
    const { np } = req.params;

    const npNumero = Number(np);

    // npNumero <= 0 se rechaza aparte de !isInteger: NotaVentaFaret y
    // NotaVentaInnpack usan 0 (no NULL) como valor "sin asignar" en
    // ZZZMasterOT (confirmado con datos reales, ver NP 22403), así que un
    // @np = 0 matchearia por accidente cualquier orden sin esa referencia.
    if (!Number.isInteger(npNumero) || npNumero <= 0) {
        return res.status(400).json({ ok: false, message: 'NP inválido' });
    }

    try {
        const pool = await getSqlServerPool();

        // Paso 1: resolver la orden real. El operador puede ingresar
        // OrdenTrabajo, Referencia 1 (NotaVentaFaret) o Referencia 2
        // (NotaVentaInnpack) — los tres identifican la misma orden en
        // ZZZMasterOT. Se resuelve primero (en vez de un solo JOIN) para
        // poder traer cliente + productos desde la MISMA orden confirmada,
        // sin ambigüedad si @np calzara por columnas distintas.
        const ordenResult = await pool.request()
            .input('np', sql.Int, npNumero)
            .query(`
                SELECT TOP 1 OrdenTrabajo, RazonSocial, CodigoCliente
                FROM ZZZMasterOT
                WHERE OrdenTrabajo = @np
                   OR NotaVentaFaret = @np
                   OR NotaVentaInnpack = @np
            `);

        const orden = ordenResult.recordset[0];

        if (!orden) {
            return res.json({
                ok: true,
                data: { cliente: null, codigoCliente: null, items: [] },
            });
        }

        // Paso 2: productos asociados a la orden real, replicando la misma
        // consulta que usa imprimir_Lista_OTS (Guía Técnica) en el FPS
        // original — ZZZProcesosProductivos filtrado por NombreCarpeta LIKE
        // '%90%'. Sin filtro de proceso: este selector debe traer TODOS los
        // productos asociados a la orden, independientemente del proceso.
        const itemsResult = await pool.request()
            .input('ot', sql.Int, orden.OrdenTrabajo)
            .query(`
                SELECT DISTINCT P.ItemCode AS codigo, P.ItemName AS nombre
                FROM ZZZProcesosProductivos P
                WHERE P.OrdenTrabajo = @ot
                  AND P.NombreCarpeta LIKE '%90%'
                  AND P.ItemCode IS NOT NULL AND P.ItemCode <> ''
                ORDER BY P.ItemCode
            `);

        // Deduplicación defensiva por código (un mismo ItemCode puede
        // repetirse en la Guía Técnica por distintas entregas/cantidades/
        // líneas — a veces con el mismo ItemName, a veces no exactamente
        // igual — el Map garantiza una sola entrada por código de todas
        // formas).
        const itemsPorCodigo = new Map();

        for (const item of itemsResult.recordset) {
            if (!itemsPorCodigo.has(item.codigo)) {
                itemsPorCodigo.set(item.codigo, item);
            }
        }

        res.json({
            ok: true,
            data: {
                cliente: orden.RazonSocial || null,
                codigoCliente: orden.CodigoCliente || null,
                items: Array.from(itemsPorCodigo.values()),
            },
        });
    } catch (error) {
        console.error('Error consultando orden de fabricación (SQL Server):', error.message);

        res.status(503).json({
            ok: false,
            message: 'No se pudo consultar el sistema de órdenes de fabricación',
            error: error.message,
        });
    }
};

module.exports = {
    obtenerOrdenFabricacion,
};
