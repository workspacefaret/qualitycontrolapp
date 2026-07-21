const express = require('express');

const router = express.Router();

const {
    crearRegistroCalidadFaretPallet,
    listarPreguntasCalidadFaretPallet,
    listarRegistrosCalidadFaretPallet,
    obtenerRegistroCalidadFaretPallet,
} = require('../controllers/calidadFaretPallet.controller');

router.post('/registros', crearRegistroCalidadFaretPallet);
router.get('/registros', listarRegistrosCalidadFaretPallet);
router.get('/registros/:id', obtenerRegistroCalidadFaretPallet);
router.get('/preguntas', listarPreguntasCalidadFaretPallet);

module.exports = router;
