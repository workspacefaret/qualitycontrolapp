const sql = require('mssql');

const config = {
  server: process.env.CALIDAD_SQL_SERVER,
  database: process.env.CALIDAD_SQL_DATABASE,
  user: process.env.CALIDAD_SQL_USER,
  password: process.env.CALIDAD_SQL_PASSWORD,
  options: {
    encrypt: process.env.CALIDAD_SQL_ENCRYPT === 'true',
    trustServerCertificate: process.env.CALIDAD_SQL_TRUST_CERT === 'true',
  },
};

let poolPromise = null;

const getCalidadSqlServerPool = () => {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(config).connect().catch((error) => {
      poolPromise = null;
      throw error;
    });
  }

  return poolPromise;
};

module.exports = { sql, getCalidadSqlServerPool };
