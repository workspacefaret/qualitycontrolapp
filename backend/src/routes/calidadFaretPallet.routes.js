const express = require('express');

const { autorizar } = require('../middleware/auth');
const { firmarRespuesta } = require('../middleware/firmarRespuesta');

const router = express.Router();

const {
    crearRegistroCalidadFaretPallet,
    listarPreguntasCalidadFaretPallet,
    listarRegistrosCalidadFaretPallet,
    obtenerRegistroCalidadFaretPallet,
    eliminarRegistroCalidadFaretPallet,
} = require('../controllers/calidadFaretPallet.controller');

router.post('/registros', crearRegistroCalidadFaretPallet);
router.get('/registros', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, listarRegistrosCalidadFaretPallet);
router.get('/registros/:id', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, obtenerRegistroCalidadFaretPallet);
router.get('/preguntas', listarPreguntasCalidadFaretPallet);
router.delete('/registros/:id', autorizar('borrar', 'AUTH_BORRADO_MODO'), eliminarRegistroCalidadFaretPallet);

module.exports = router;
