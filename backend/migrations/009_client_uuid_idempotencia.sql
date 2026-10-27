-- Idempotencia de envíos desde la app: un reintento (timeout, reconexión, sincronización offline) con el mismo
-- client_uuid no crea un segundo registro ni duplica sus fotos. Motor: SQL Server (calidad_db).
-- Aditiva e idempotente (re-ejecutable). Reversible: 009_client_uuid_idempotencia_rollback.sql.
--
-- * client_uuid es NULL en los registros históricos y en los enviados por APK anteriores (sin dedupe, como hoy).
-- * Índice único FILTRADO (solo filas con client_uuid): los NULL pueden repetirse sin límite.
-- * Los índices filtrados exigen QUOTED_IDENTIFIER ON en las sesiones que escriben en la tabla (es el valor por
--   defecto de SqlClient, tedious/mssql, ODBC y SSMS).
-- * PERMISO NECESARIO de la 008: la cuenta de la app (quality_control_backend_sql) tiene GRANT explícito tabla por
--   tabla y NO puede leer operadores_maquina (creada en la 008 sin GRANT). Sin este SELECT, el contexto QR y el
--   catálogo offline del backend nuevo fallarían con 500. Es el único permiso nuevo (solo lectura, solo esa tabla).
-- Ejecutar con una cuenta con DDL, tras respaldar calidad_db y ANTES de desplegar el backend que usa estos cambios.
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.operadores_maquina', N'U') IS NOT NULL AND USER_ID(N'quality_control_backend_sql') IS NOT NULL
    GRANT SELECT ON dbo.operadores_maquina TO [quality_control_backend_sql];

IF COL_LENGTH(N'registros_control', N'client_uuid') IS NULL
    ALTER TABLE registros_control ADD client_uuid NVARCHAR(36) NULL;

IF COL_LENGTH(N'registros_calidad_faret', N'client_uuid') IS NULL
    ALTER TABLE registros_calidad_faret ADD client_uuid NVARCHAR(36) NULL;

-- EXEC: la columna recién agregada no existe aún cuando se compila este lote.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_registros_control_client_uuid' AND object_id = OBJECT_ID(N'registros_control'))
    EXEC (N'CREATE UNIQUE INDEX UX_registros_control_client_uuid ON registros_control (client_uuid) WHERE client_uuid IS NOT NULL');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_registros_calidad_faret_client_uuid' AND object_id = OBJECT_ID(N'registros_calidad_faret'))
    EXEC (N'CREATE UNIQUE INDEX UX_registros_calidad_faret_client_uuid ON registros_calidad_faret (client_uuid) WHERE client_uuid IS NOT NULL');

COMMIT TRANSACTION;

-- Verificación posterior:
--   SELECT OBJECT_NAME(object_id) tabla, name, is_unique, filter_definition FROM sys.indexes WHERE name LIKE 'UX_%client_uuid';
--   SELECT COL_LENGTH('registros_control','client_uuid') a, COL_LENGTH('registros_calidad_faret','client_uuid') b;
--   EXECUTE AS USER = 'quality_control_backend_sql'; SELECT COUNT(*) FROM operadores_maquina; REVERT;
