const express = require('express');
const { autorizar } = require('../middleware/auth');
const { listar, crear, actualizar, listarAuditoria } = require('../controllers/adminPlanta.controller');

const router = express.Router();

// Administración de planta: siempre exige sesión y rol (sin modo observar/off). El acceso fino por usuario lo decide el QCC.
const admin = autorizar('administrar', 'AUTH_ADMIN_PLANTA_MODO', { obligatorio: true });

router.get('/:empresa/auditoria', admin, listarAuditoria);
router.get('/:empresa/:entidad', admin, listar);
router.post('/:empresa/:entidad', admin, crear);
router.put('/:empresa/:entidad/:id', admin, actualizar);

module.exports = router;
