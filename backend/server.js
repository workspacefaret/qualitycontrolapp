const express = require('express');
const cors = require('cors');

require('dotenv').config();

const { getCalidadSqlServerPool } = require('./src/config/calidadSqlServerPool');

const catalogosRoutes = require('./src/routes/catalogos.routes');
const controlRoutes = require('./src/routes/control.routes');
const calidadFaretRoutes = require('./src/routes/calidadFaret.routes');
const calidadFaretPalletRoutes = require('./src/routes/calidadFaretPallet.routes');
const calidadFaretOperadoresRoutes = require('./src/routes/calidadFaretOperadores.routes');
const ordenFabricacionRoutes = require('./src/routes/ordenFabricacion.routes');
const bobinaRoutes = require('./src/routes/bobina.routes');
const productoTerminadoRoutes = require('./src/routes/productoTerminado.routes');

const app = express();

const allowedOrigins = [
  'http://127.0.0.1:8080',
  'http://localhost:8080',
  'http://10.10.50.21:8080',
  'https://workspace.faret.cl',
  'https://qualitycontrol.faret.cl',
];

const corsOptions = {
  origin: function (origin, callback) {
    if (!origin || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }

    return callback(new Error(`Origen no permitido por CORS: ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  optionsSuccessStatus: 204,
};

app.use(cors(corsOptions));
app.options(/.*/, cors(corsOptions));

app.use(express.json());
// Solo se sirven imágenes y PDF (todo el histórico es .jpg/.jpeg/.png); cualquier otra extensión (html, svg, js...) da 404
// y el navegador no puede reinterpretar el tipo ni ejecutar el contenido.
app.use('/uploads', (req, res, next) => {
  if (!/\.(jpe?g|png|pdf)$/i.test(req.path)) return res.status(404).end();
  res.set({
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; sandbox",
  });
  next();
}, express.static('uploads', { index: false, dotfiles: 'ignore' }));

const PORT = process.env.PORT || 3000;

app.get('/api/health', async (req, res) => {
  try {
    const poolConn = await getCalidadSqlServerPool();

    await poolConn.request().query('SELECT 1');

    res.json({
      ok: true,
      message: 'Backend y SQL Server (calidad_db) operativos',
      database: process.env.CALIDAD_SQL_DATABASE,
    });
  } catch (error) {
    console.error('Error SQL Server:', error.message);

    res.status(500).json({
      ok: false,
      message: 'Error conexión SQL Server',
      error: error.message,
    });
  }
});

app.use('/api/catalogos', catalogosRoutes);
app.use('/api/control', controlRoutes);
app.use('/api/calidad-faret/operadores', calidadFaretOperadoresRoutes);
app.use('/api/calidad-faret', calidadFaretRoutes);
app.use('/api/calidad-faret-pallet', calidadFaretPalletRoutes);
app.use('/api/orden-fabricacion', ordenFabricacionRoutes);
app.use('/api/bobina', bobinaRoutes);
app.use('/api/producto-terminado', productoTerminadoRoutes);

app.listen(PORT, () => {
  console.log(`Servidor backend en puerto ${PORT}`);
});
