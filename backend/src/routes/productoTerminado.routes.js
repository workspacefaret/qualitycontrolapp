const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload, limitarPeticion, MAX_BYTES } = require('../utils/uploads');
const { autorizar } = require('../middleware/auth');
const { firmarRespuesta } = require('../middleware/firmarRespuesta');

const router = express.Router();

const {
    crearRegistroProductoTerminado,
    listarRegistrosProductoTerminado,
    obtenerRegistroProductoTerminado,
} = require('../controllers/productoTerminado.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/producto_terminado'));

// Máx. 40 fotos por inspección (histórico real: <30 en total). Tope de petición: 40 x 25 MB.
const MAX_FOTOS = 40;
router.post('/registros', limitarPeticion(MAX_FOTOS * MAX_BYTES + 1024 * 1024), upload.array('fotos', MAX_FOTOS), validarContenido, crearRegistroProductoTerminado);
router.get('/registros', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, listarRegistrosProductoTerminado);
router.get('/registros/:id', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, obtenerRegistroProductoTerminado);

router.use(manejarErroresUpload);

module.exports = router;
