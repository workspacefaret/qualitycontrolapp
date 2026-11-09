-- Deja datos reales (commit) creados con el catálogo nuevo y copia testigo de lo que el rollback debe respaldar.
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'%test%' THROW 59001, N'Solo en base de pruebas.', 1;
DROP TABLE IF EXISTS dbo.zz_pre_areas, dbo.zz_pre_eventos, dbo.zz_pre_auditoria, dbo.zz_pre_defectos_evento;

EXEC sp_set_session_context N'usuario', N'tester.calidad';
EXEC sp_set_session_context N'motivo', N'edicion previa al rollback';
UPDATE dbo.calidad_faret_eventos SET criticidad = N'Critico' WHERE id_evento = N'OFF-011';   -- edición legítima del catálogo (queda auditada)

EXECUTE AS USER = N'quality_control_backend_sql';
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad)
SELECT id, N'Abolladura de mantilla de impresión o barniz', N'OFF-001', N'Critico' FROM dbo.registros_calidad_faret WHERE nv_faret = N'NV-1001';
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad)
SELECT id, N'Calce de barniz.', N'SER-001', N'Critico' FROM dbo.registros_calidad_faret WHERE nv_faret = N'NV-1003';
REVERT;

SELECT cod_area, nombre, area_control, orden, estado, created_at, created_by, updated_at, updated_by, CONVERT(BINARY(8), row_version) AS row_version INTO dbo.zz_pre_areas FROM dbo.calidad_faret_areas;
SELECT id_evento, cod_area, tipo_registro, defecto, criticidad, estado, orden, defecto_origen, criticidad_origen, estado_origen, observacion_origen, texto_documento,
       requiere_aprobacion, aprobacion, aprobado_por, aprobado_at, aprobacion_ref, created_at, created_by, updated_at, updated_by, CONVERT(BINARY(8), row_version) AS row_version
  INTO dbo.zz_pre_eventos FROM dbo.calidad_faret_eventos;
SELECT * INTO dbo.zz_pre_auditoria FROM dbo.calidad_faret_catalogo_auditoria;
SELECT id, registro_id, defecto, id_evento, criticidad INTO dbo.zz_pre_defectos_evento FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL;
SELECT (SELECT COUNT(*) FROM dbo.zz_pre_defectos_evento) AS defectos_con_evento, (SELECT COUNT(*) FROM dbo.zz_pre_auditoria) AS filas_auditoria;
