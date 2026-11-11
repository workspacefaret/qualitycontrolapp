-- Rollback de la 011. Quita los permisos de edición y la bitácora (se pierde el historial de ediciones: respaldar antes si importa).
-- No toca datos de inspecciones. Ejecutar con cuenta con DDL.
SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRAN;
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    IF OBJECT_ID(N'dbo.inspecciones_faret_auditoria', N'U') IS NOT NULL REVOKE SELECT, INSERT ON dbo.inspecciones_faret_auditoria FROM [quality_control_backend_sql];
    REVOKE DELETE ON dbo.registro_calidad_faret_defectos FROM [quality_control_backend_sql];
    REVOKE UPDATE (resultado, observacion) ON dbo.registro_calidad_faret_pallet_respuestas FROM [quality_control_backend_sql];
    REVOKE UPDATE (tipo_material, dimension, fibra, numero_pallet, numero_pasadas_prensa, observaciones, area_control, operador, operador_otro, maquina) ON dbo.registros_calidad_faret_pallet FROM [quality_control_backend_sql];
    REVOKE UPDATE (nv_faret, nv_vb_aprobado, n_pliego, n_pasada, n_item, pliego_control_n, observaciones, area_control, operador, operador_otro, maquina, presenta_defectos, area_defecto, tipo_folia, accion_correctiva) ON dbo.registros_calidad_faret FROM [quality_control_backend_sql];
    -- El borrado lógico (UPDATE de la columna eliminado) lo concedió el aprovisionamiento original y no se toca.
END
IF OBJECT_ID(N'dbo.TR_inspecciones_faret_auditoria_inmutable', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_inspecciones_faret_auditoria_inmutable;
IF OBJECT_ID(N'dbo.inspecciones_faret_auditoria', N'U') IS NOT NULL DROP TABLE dbo.inspecciones_faret_auditoria;
COMMIT TRAN;
PRINT N'011 revertida.';
