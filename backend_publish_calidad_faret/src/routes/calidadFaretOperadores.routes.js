const express = require('express');

const router = express.Router();

const {
    listarOperadoresCalidadFaret,
} = require('../controllers/calidadFaretOperadores.controller');

router.get('/', listarOperadoresCalidadFaret);

module.exports = router;
