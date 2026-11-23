-- Reversa de 015_clasificacion_pallets.sql. SQL Server (calidad_db).
-- ELIMINA las dos tablas nuevas Y SU CONTENIDO (las clasificaciones registradas). No toca registros_control ni ninguna
-- inspección. Respaldar antes si ya hay clasificaciones reales:  SELECT * INTO ... FROM pallet_clasificaciones.
-- Tras revertir, desplegar también el backend anterior (el nuevo escribe en estas tablas cuando recibe pallets).
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.pallet_clasificacion_defectos', N'U') IS NOT NULL DROP TABLE dbo.pallet_clasificacion_defectos;
IF OBJECT_ID(N'dbo.pallet_clasificaciones', N'U') IS NOT NULL DROP TABLE dbo.pallet_clasificaciones;

COMMIT TRANSACTION;
