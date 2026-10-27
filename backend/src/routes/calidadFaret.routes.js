const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload, limitarPeticion, MAX_BYTES } = require('../utils/uploads');
const { autorizar } = require('../middleware/auth');
const { firmarRespuesta } = require('../middleware/firmarRespuesta');

const router = express.Router();

const {
    crearRegistroCalidadFaret,
    listarRegistrosCalidadFaret,
    obtenerResumenCalidadFaret,
    obtenerResumenMaquinasCalidadFaret,
    listarAdjuntosRegistroCalidadFaret,
    eliminarRegistroCalidadFaret,
} = require('../controllers/calidadFaret.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/calidad_faret'));

// Máx. 5 archivos de 25 MB por inspección (+ margen para los campos del formulario).
router.post('/registros', limitarPeticion(5 * MAX_BYTES + 1024 * 1024), upload.array('archivos', 5), validarContenido, crearRegistroCalidadFaret);
router.get('/registros', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, listarRegistrosCalidadFaret);
router.get('/resumen', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, obtenerResumenCalidadFaret);
router.get('/maquinas/resumen', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, obtenerResumenMaquinasCalidadFaret);
router.get('/registros/:id/adjuntos', autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta, listarAdjuntosRegistroCalidadFaret);
router.delete('/registros/:id', autorizar('borrar', 'AUTH_BORRADO_MODO'), eliminarRegistroCalidadFaret);

router.use(manejarErroresUpload);

module.exports = router;
