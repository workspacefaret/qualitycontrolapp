-- Rollback de 013 (administración de planta). Elimina las tablas nuevas y la columna `activo` de calidad_faret_operadores.
-- ADVERTENCIA: borra los cambios hechos desde el módulo (altas/bajas de máquinas y operadores FARET) y la auditoría.
-- Antes de ejecutarlo, la app móvil debe estar leyendo su catálogo local (versión anterior) o los selectores quedarán vacíos.
-- Los permisos concedidos sobre tablas INNPACK no se revocan aquí (son inocuos sin el backend /api/admin-planta).
SET XACT_ABORT ON;
BEGIN TRAN;

IF OBJECT_ID(N'dbo.calidad_faret_maquinas', N'U') IS NOT NULL DROP TABLE dbo.calidad_faret_maquinas;
IF OBJECT_ID(N'dbo.calidad_faret_operadores_area', N'U') IS NOT NULL DROP TABLE dbo.calidad_faret_operadores_area;
IF OBJECT_ID(N'dbo.admin_planta_auditoria', N'U') IS NOT NULL DROP TABLE dbo.admin_planta_auditoria;

IF COL_LENGTH(N'dbo.calidad_faret_operadores', N'activo') IS NOT NULL
BEGIN
    EXEC (N'ALTER TABLE dbo.calidad_faret_operadores DROP CONSTRAINT DF_calidad_faret_operadores_activo');
    EXEC (N'ALTER TABLE dbo.calidad_faret_operadores DROP COLUMN activo');
END;

COMMIT TRAN;
