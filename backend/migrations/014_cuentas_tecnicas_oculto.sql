-- Cuentas técnicas ocultas en Administración de planta (QCC Desktop). Motor: SQL Server (calidad_db).
-- Aditiva e idempotente (re-ejecutable). Reversible: 014_cuentas_tecnicas_oculto_rollback.sql.
--
-- Qué hace: agrega la columna `oculto BIT NOT NULL DEFAULT 0` a las dos tablas cuyas filas se listan como "Inspectores":
--   dbo.usuarios                  (INNPACK, rol 'operador')
--   dbo.calidad_faret_operadores  (FARET)
-- Todas las filas existentes quedan con oculto = 0: ESTA migración NO oculta ninguna cuenta. Marcar cuentas concretas es un paso
-- aparte, posterior a la revisión del listado (ver 014_auditoria_cuentas_tecnicas_SOLO_LECTURA.sql y 014_marcar_cuentas_ocultas.sql).
--
-- Qué NO toca: contraseñas, roles, el campo `activo`, ni el login/autenticación (el backend solo filtra los listados de
-- Administración de planta). La columna es de solo lectura para la cuenta de la app: no se concede UPDATE sobre `oculto`,
-- así que solo se cambia con SQL por el DBA.
--
-- Cómo ejecutar: cuenta con DDL, tras respaldar calidad_db, ANTES de desplegar el backend que usa `oculto`.
-- Sin GO: un solo lote; si algo falla se revierte todo. Archivo UTF-8 sin BOM.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRAN;

IF OBJECT_ID(N'dbo.usuarios', N'U') IS NULL THROW 51400, N'Falta dbo.usuarios.', 1;
IF OBJECT_ID(N'dbo.calidad_faret_operadores', N'U') IS NULL THROW 51401, N'Falta dbo.calidad_faret_operadores.', 1;

IF COL_LENGTH(N'dbo.usuarios', N'oculto') IS NULL
    EXEC (N'ALTER TABLE dbo.usuarios ADD oculto BIT NOT NULL CONSTRAINT DF_usuarios_oculto DEFAULT 0');

IF COL_LENGTH(N'dbo.calidad_faret_operadores', N'oculto') IS NULL
    EXEC (N'ALTER TABLE dbo.calidad_faret_operadores ADD oculto BIT NOT NULL CONSTRAINT DF_calidad_faret_operadores_oculto DEFAULT 0');

-- Lectura de la columna nueva para la app (inocuo si ya tiene SELECT a nivel de tabla). Sin UPDATE: nadie la cambia desde la app.
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    EXEC (N'
    GRANT SELECT (oculto) ON dbo.usuarios TO [quality_control_backend_sql];
    GRANT SELECT (oculto) ON dbo.calidad_faret_operadores TO [quality_control_backend_sql];');
END;

COMMIT TRAN;

-- Verificación (esperado: ambas columnas existen y 0 filas ocultas):
--   SELECT COL_LENGTH(N'dbo.usuarios', N'oculto'), COL_LENGTH(N'dbo.calidad_faret_operadores', N'oculto');
--   SELECT (SELECT COUNT(*) FROM dbo.usuarios WHERE oculto = 1) AS usuarios_ocultos,
--          (SELECT COUNT(*) FROM dbo.calidad_faret_operadores WHERE oculto = 1) AS faret_ocultos;
