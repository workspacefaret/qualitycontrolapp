-- Reversa de 015_admin_defectos_faret.sql. SQL Server (calidad_db). Respaldar calidad_db antes.
-- 1) Quita los permisos nuevos de la cuenta de la app (vuelve a SELECT/INSERT que tenía antes en lo demás).
-- 2) Quita parametros_control_visual.empresa SOLO si no hay defectos propios de FARET: esas filas pueden estar referenciadas por
--    inspecciones de Producto Terminado (FK) y borrarlas o dejarlas visibles a INNPACK perdería/ensuciaría datos. Si existen, el script
--    deja la columna, lo avisa y termina sin error (los permisos sí se retiran).
-- Los defectos/preguntas creados en calidad_faret_eventos y calidad_faret_pallet_preguntas no se borran (los eventos no se pueden borrar
-- por trigger; quedan activos o dados de baja según estén). Para ocultarlos, darlos de baja antes con el panel.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRAN;

IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    EXEC (N'
    REVOKE UPDATE (defecto, criticidad, estado, orden) ON dbo.calidad_faret_eventos FROM [quality_control_backend_sql];
    REVOKE INSERT ON dbo.calidad_faret_eventos FROM [quality_control_backend_sql];
    REVOKE UPDATE (texto, orden, activo) ON dbo.calidad_faret_pallet_preguntas FROM [quality_control_backend_sql];
    REVOKE INSERT ON dbo.calidad_faret_pallet_preguntas FROM [quality_control_backend_sql];
    REVOKE UPDATE (nombre, criticidad, activo) ON dbo.parametros_control_visual FROM [quality_control_backend_sql];
    REVOKE INSERT ON dbo.parametros_control_visual FROM [quality_control_backend_sql];
    ');
END

IF COL_LENGTH(N'dbo.parametros_control_visual', N'empresa') IS NOT NULL
BEGIN
    DECLARE @propios INT;
    EXEC sp_executesql N'SELECT @n = COUNT(*) FROM dbo.parametros_control_visual WHERE empresa IS NOT NULL', N'@n INT OUTPUT', @n = @propios OUTPUT;
    IF @propios = 0
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_parametros_control_visual_empresa' AND parent_object_id = OBJECT_ID(N'dbo.parametros_control_visual'))
            EXEC (N'ALTER TABLE dbo.parametros_control_visual DROP CONSTRAINT CK_parametros_control_visual_empresa');
        EXEC (N'ALTER TABLE dbo.parametros_control_visual DROP COLUMN empresa');
        PRINT N'Columna empresa eliminada.';
    END
    ELSE
        PRINT N'AVISO: hay defectos propios de FARET; la columna empresa se conserva (permisos retirados).';
END

COMMIT;
PRINT N'Rollback 015 completado.';
