const express = require('express');

const router = express.Router();

const {
    getUsuarios,
    getProcesos,
    getMaquinas,
    getParametrosVisuales,
    getCatalogoOffline,
} = require('../controllers/catalogos.controller');

router.get('/usuarios', getUsuarios);

router.get('/offline', getCatalogoOffline);

router.get('/procesos', getProcesos);

router.get('/maquinas', getMaquinas);

router.get('/parametros-visuales/:procesoId', getParametrosVisuales);

module.exports = router;