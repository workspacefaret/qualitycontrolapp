const sql = require('mssql');

const config = {
  server: process.env.SAP_SQL_SERVER,
  database: process.env.SAP_SQL_DATABASE,
  user: process.env.SAP_SQL_USER,
  password: process.env.SAP_SQL_PASSWORD,
  options: {
    encrypt: process.env.SAP_SQL_ENCRYPT === 'true',
    trustServerCertificate: process.env.SAP_SQL_TRUST_CERT === 'true',
  },
};

let poolPromise = null;

const getSapSqlServerPool = () => {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(config).connect().catch((error) => {
      poolPromise = null;
      throw error;
    });
  }

  return poolPromise;
};

module.exports = { sql, getSapSqlServerPool };
