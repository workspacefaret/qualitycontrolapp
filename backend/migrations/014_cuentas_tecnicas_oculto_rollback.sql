-- Rollback de 014 (cuentas técnicas ocultas). Elimina la columna `oculto` de dbo.usuarios y dbo.calidad_faret_operadores.
-- ADVERTENCIA: las cuentas que estuvieran marcadas como ocultas volverían a aparecer en los listados de Administración de planta.
-- Antes de ejecutarlo, el backend que filtra por `oculto` debe estar revertido (de lo contrario sus consultas fallarían).
-- No toca contraseñas, roles ni `activo`. Los GRANT SELECT (oculto) se eliminan solos con la columna.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRAN;

IF COL_LENGTH(N'dbo.usuarios', N'oculto') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_usuarios_oculto')
        EXEC (N'ALTER TABLE dbo.usuarios DROP CONSTRAINT DF_usuarios_oculto');
    EXEC (N'ALTER TABLE dbo.usuarios DROP COLUMN oculto');
END;

IF COL_LENGTH(N'dbo.calidad_faret_operadores', N'oculto') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = N'DF_calidad_faret_operadores_oculto')
        EXEC (N'ALTER TABLE dbo.calidad_faret_operadores DROP CONSTRAINT DF_calidad_faret_operadores_oculto');
    EXEC (N'ALTER TABLE dbo.calidad_faret_operadores DROP COLUMN oculto');
END;

COMMIT TRAN;
