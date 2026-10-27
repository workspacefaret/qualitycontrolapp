const express = require('express');

const { autorizar } = require('../middleware/auth');
const { rutaSegura, existe, urlFirmada, TTL_SEGUNDOS } = require('../utils/urlsFirmadas');

const router = express.Router();

// GET /api/adjuntos/firmar?ruta=/uploads/control/archivo.jpg  (requiere sesión con permiso de lectura)
// Sirve a los clientes que obtienen la ruta de la foto desde otra API (p. ej. INNPACK) y necesitan una URL temporal.
router.get('/firmar', autorizar('leer', 'AUTH_CONSULTAS_MODO'), (req, res) => {
    const ruta = rutaSegura(req.query.ruta);
    if (!ruta || !existe(ruta)) return res.status(404).json({ ok: false, message: 'Archivo no encontrado.' });
    // En modo observar un cliente sin token podría llegar aquí: no se firma sin identidad verificada.
    if (!req.auth) return res.status(401).json({ ok: false, message: 'Autenticación requerida.' });
    return res.json({ ok: true, data: { url: urlFirmada(ruta), expiraEnSegundos: TTL_SEGUNDOS } });
});

module.exports = router;
