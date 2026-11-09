-- Reversa de 010_catalogo_eventos_calidad_faret.sql. SQL Server (calidad_db).
-- SIN PÉRDIDA DE INFORMACIÓN: antes de quitar nada, copia a tablas bak010_<fecha>_* (que este script NUNCA borra):
--   * las 2 tablas de catálogo y la auditoría completas;
--   * id_evento + criticidad de cada defecto ya registrado con el catálogo (registro_calidad_faret_defectos).
-- El texto del defecto (columna defecto) de esas inspecciones NO se toca: sigue en su tabla original.
-- No modifica ni elimina ninguna fila preexistente de registros_calidad_faret ni de registro_calidad_faret_defectos
-- (solo quita las 2 columnas/índice/FK/CHECK/trigger que agregó la 010). No toca INNPACK ni otros módulos.
--
-- Protección: si ya existen defectos registrados con id_evento (la Etapa 2 está en uso), el script SE NIEGA a continuar
-- salvo que se ponga @permitir_con_datos = 1 (en ese caso los respalda primero y luego sigue).
-- Re-ejecutable: si ya está revertido, no hace nada. Si después se vuelve a aplicar la 010, el catálogo se recarga
-- desde el Excel (las ediciones del catálogo hechas entre medias quedan solo en las tablas bak010_*).
DECLARE @permitir_con_datos BIT = 0;

SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 5000;   -- si no obtiene el bloqueo en 5 s, cancela sin cambios (reintentar)

IF OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL
   AND OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NULL
   AND OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria', N'U') IS NULL
   AND COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NULL
   AND COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') IS NULL
BEGIN
    PRINT N'La migración 010 no está aplicada: nada que revertir.';
    RETURN;
END

BEGIN TRANSACTION;

DECLARE @con_datos INT = 0;
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NOT NULL
    EXEC sp_executesql N'SELECT @n = COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL',
                       N'@n INT OUTPUT', @n = @con_datos OUTPUT;

IF @con_datos > 0 AND @permitir_con_datos = 0
    THROW 51100, N'Hay defectos registrados con id_evento. Para revertir igualmente (con respaldo previo) use @permitir_con_datos = 1.', 1;

-- 1. Respaldo (nombres con fecha y hora: nunca se pisa un respaldo anterior)
DECLARE @s NVARCHAR(14) = CONVERT(NVARCHAR(8), GETDATE(), 112) + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), N':', N'');   -- yyyyMMddHHmmss sin FORMAT (que depende de CLR/.NET)
DECLARE @sql NVARCHAR(MAX);

IF OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NOT NULL
BEGIN
    SET @sql = N'SELECT cod_area, nombre, area_control, orden, estado, created_at, created_by, updated_at, updated_by,
                        CONVERT(BINARY(8), row_version) AS row_version
                 INTO dbo.bak010_' + @s + N'_areas FROM dbo.calidad_faret_areas';
    EXEC (@sql);
END
IF OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NOT NULL
BEGIN
    SET @sql = N'SELECT id_evento, cod_area, tipo_registro, defecto, criticidad, estado, orden, defecto_origen, criticidad_origen,
                        estado_origen, observacion_origen, texto_documento, requiere_aprobacion, aprobacion, aprobado_por,
                        aprobado_at, aprobacion_ref, created_at, created_by, updated_at, updated_by,
                        CONVERT(BINARY(8), row_version) AS row_version
                 INTO dbo.bak010_' + @s + N'_eventos FROM dbo.calidad_faret_eventos';
    EXEC (@sql);
END
IF OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria', N'U') IS NOT NULL
BEGIN
    SET @sql = N'SELECT * INTO dbo.bak010_' + @s + N'_auditoria FROM dbo.calidad_faret_catalogo_auditoria';
    EXEC (@sql);
END
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NOT NULL
BEGIN
    SET @sql = N'SELECT id, registro_id, defecto, id_evento, criticidad
                 INTO dbo.bak010_' + @s + N'_defectos_evento FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL';
    EXEC (@sql);
END

-- 2. Quitar lo que agregó la 010 sobre registro_calidad_faret_defectos (orden: trigger, índice, CHECK, FK, columnas)
IF OBJECT_ID(N'dbo.TR_registro_calidad_faret_defectos_evento', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_registro_calidad_faret_defectos_evento;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_registro_calidad_faret_defectos_id_evento' AND object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    DROP INDEX IX_registro_calidad_faret_defectos_id_evento ON dbo.registro_calidad_faret_defectos;
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_registro_calidad_faret_defectos_evento_crit' AND parent_object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    ALTER TABLE dbo.registro_calidad_faret_defectos DROP CONSTRAINT CK_registro_calidad_faret_defectos_evento_crit;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_registro_calidad_faret_defectos_evento' AND parent_object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    ALTER TABLE dbo.registro_calidad_faret_defectos DROP CONSTRAINT FK_registro_calidad_faret_defectos_evento;
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NOT NULL
    ALTER TABLE dbo.registro_calidad_faret_defectos DROP COLUMN id_evento;
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') IS NOT NULL
    ALTER TABLE dbo.registro_calidad_faret_defectos DROP COLUMN criticidad;

-- 3. Quitar vista y tablas de la 010 (sus triggers y permisos se van con ellas). Ya están respaldadas arriba.
IF OBJECT_ID(N'dbo.vw_calidad_faret_eventos_operables', N'V') IS NOT NULL DROP VIEW dbo.vw_calidad_faret_eventos_operables;
IF OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NOT NULL DROP TABLE dbo.calidad_faret_eventos;
IF OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NOT NULL DROP TABLE dbo.calidad_faret_areas;
IF OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria', N'U') IS NOT NULL DROP TABLE dbo.calidad_faret_catalogo_auditoria;

COMMIT TRANSACTION;

SELECT @s AS sufijo_respaldo, @con_datos AS defectos_con_evento_respaldados;
-- Respaldos creados: SELECT name FROM sys.tables WHERE name LIKE 'bak010[_]%';
-- Cuando ya no se necesiten (decisión manual, nunca automática): DROP TABLE dbo.bak010_<fecha>_<nombre>;
