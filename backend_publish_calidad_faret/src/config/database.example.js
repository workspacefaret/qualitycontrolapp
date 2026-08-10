const mysql = require('mysql2/promise');

const pool = mysql.createPool({
    host: 'TU_HOST',
    port: 3306,
    user: 'TU_USUARIO',
    password: 'TU_PASSWORD',
    database: 'TU_DATABASE',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
});

module.exports = pool;
