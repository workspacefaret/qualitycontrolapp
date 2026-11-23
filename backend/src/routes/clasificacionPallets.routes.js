const express = require('express');

const { autorizar } = require('../middleware/auth');
const { firmarRespuesta } = require('../middleware/firmarRespuesta');
const { limitarConsultasTarja } = require('../middleware/limiteSolicitudes');
const {
    obtenerTarja, listarClasificaciones, resumenClasificaciones, defectosPorClasificacion,
    obtenerClasificacion, obtenerHistorial, anularClasificacion,
} = require('../controllers/clasificacionPallets.controller');

const router = express.Router();

// Formularios (sin login, igual que /api/orden-fabricacion y /api/bobina: los operadores de la app no tienen sesión): solo lectura de FPS,
// con límite por IP porque cada llamada consulta FPS.
router.get('/tarja/:codigo', limitarConsultasTarja, obtenerTarja);

// Lectura para Photino (mismo esquema de autenticación que el resto de las consultas) y anulación (permiso de borrado).
const leer = [autorizar('leer', 'AUTH_CONSULTAS_MODO'), firmarRespuesta];
router.get('/clasificaciones', ...leer, listarClasificaciones);
router.get('/clasificaciones/resumen', ...leer, resumenClasificaciones);
router.get('/clasificaciones/defectos', ...leer, defectosPorClasificacion);
router.get('/clasificaciones/:id', ...leer, obtenerClasificacion);
router.get('/historial/:codigo', ...leer, obtenerHistorial);
router.post('/clasificaciones/:id/anular', autorizar('borrar', 'AUTH_BORRADO_MODO'), anularClasificacion);

module.exports = router;
