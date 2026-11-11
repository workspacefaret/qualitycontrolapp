const express = require('express');

const { autorizar } = require('../middleware/auth');
const { firmarRespuesta } = require('../middleware/firmarRespuesta');
const { actualizarRegistroCalidadFaretPallet, auditoriaCalidadFaretPallet } = require('../controllers/inspeccionesEdicion.controller');

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
// Edición (ADMIN, ADMIN_TI, INSPECTOR): siempre exige sesión y rol, sin modo observar/off.
router.put('/registros/:id', autorizar('editar', 'AUTH_EDICION_MODO', { obligatorio: true }), actualizarRegistroCalidadFaretPallet);
router.get('/registros/:id/auditoria', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, auditoriaCalidadFaretPallet);

module.exports = router;
