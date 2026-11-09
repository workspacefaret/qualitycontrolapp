-- Preparación de la base de PRUEBAS aislada (LocalDB): cuenta de la app con los permisos reales + datos históricos de ejemplo.
-- Réplica de lo que hace provisionar_quality_control_backend_sql.py (SELECT/INSERT por tabla, UPDATE solo de eliminado).
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'%test%' THROW 59001, N'Este script solo corre en una base de pruebas (nombre con "test").', 1;

IF USER_ID(N'quality_control_backend_sql') IS NULL CREATE USER [quality_control_backend_sql] WITHOUT LOGIN;

DECLARE @t TABLE (nombre SYSNAME, sel BIT, ins BIT);
INSERT INTO @t VALUES
 (N'calidad_faret_operadores',1,1),(N'calidad_faret_pallet_preguntas',1,0),(N'ensayos_laboratorio',1,0),(N'formularios_control',1,0),
 (N'maquinas',1,0),(N'materiales',1,0),(N'origenes_problema',1,0),(N'parametros_control_visual',1,0),(N'procesos',1,0),
 (N'registro_adjuntos',0,1),(N'registro_calidad_faret_adjuntos',1,1),(N'registro_calidad_faret_defectos',1,1),
 (N'registro_calidad_faret_pallet_respuestas',1,1),(N'registro_control_bobinas',1,1),(N'registro_ensayos',0,1),(N'registro_fallas_visuales',0,1),
 (N'registro_pt_hallazgo_defectos',1,1),(N'registro_pt_hallazgos',1,1),(N'registro_pt_pallets',1,1),
 (N'registros_calidad_faret',1,1),(N'registros_calidad_faret_pallet',1,1),(N'registros_control',1,1),
 (N'registros_producto_terminado',1,1),(N'tipos_onda',1,0),(N'usuarios',1,0);
DECLARE @n SYSNAME, @s BIT, @i BIT, @sql NVARCHAR(400);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT nombre, sel, ins FROM @t;
OPEN c; FETCH NEXT FROM c INTO @n, @s, @i;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'dbo.' + @n, N'U') IS NOT NULL
    BEGIN
        IF @s = 1 BEGIN SET @sql = N'GRANT SELECT ON dbo.' + QUOTENAME(@n) + N' TO [quality_control_backend_sql]'; EXEC (@sql); END
        IF @i = 1 BEGIN SET @sql = N'GRANT INSERT ON dbo.' + QUOTENAME(@n) + N' TO [quality_control_backend_sql]'; EXEC (@sql); END
    END
    FETCH NEXT FROM c INTO @n, @s, @i;
END
CLOSE c; DEALLOCATE c;
GRANT UPDATE (eliminado) ON dbo.registros_calidad_faret TO [quality_control_backend_sql];
GRANT UPDATE (eliminado) ON dbo.registros_calidad_faret_pallet TO [quality_control_backend_sql];

-- Histórico de ejemplo (con nombres de defecto del catálogo ANTERIOR, incluidos los que el Excel retira)
INSERT INTO dbo.registros_calidad_faret (nv_faret, nv_vb_aprobado, area_control, operador, maquina, presenta_defectos, area_defecto, tipo_folia, fecha_registro, hora_registro, observaciones)
VALUES (N'NV-1001', 1, N'03-OFFSET',     N'AXEL CRUZ',   N'XL - 3',    1, N'03-OFFSET',     NULL, '2026-10-01', '10:00:00', N'hist 1'),
       (N'NV-1002', 1, N'03-OFFSET',     N'DEDIER LEIVA',N'KBA 2',     1, N'03-OFFSET',     NULL, '2026-10-02', '11:00:00', N'hist 2'),
       (N'NV-1003', 0, N'04-SERIGRAFÍA', N'ALEJANDRO ALBORNOZ', N'SAKURAI', 1, N'04-SERIGRAFÍA', NULL, '2026-10-03', '12:00:00', N'hist 3'),
       (N'NV-1004', 1, N'05-FOLIA',      N'JUAN SALDIAS',N'FOLIA 2',   1, N'05-FOLIA', N'ORO MATE STANDARD LUXOR 428 KURZ', '2026-10-04', '13:00:00', NULL),
       (N'NV-1005', 1, N'07-TROQUELADO', N'SERGIO TORO', N'BOBST 104 - 1', 0, NULL,        NULL, '2026-10-05', '14:00:00', NULL),
       (N'NV-1006', 1, N'13-CORTE Y DIMENSIONADO', N'JUAN PLAZA', N'GUILLOTINA 1 POLAR 137', 0, NULL, NULL, '2026-10-06', '15:00:00', NULL);
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto)
SELECT r.id, d.defecto FROM dbo.registros_calidad_faret r JOIN (VALUES
  (N'NV-1001', N'DIFERENCIA DE TONO'), (N'NV-1001', N'DEFECTO DE SECADO'), (N'NV-1002', N'PROBLEMA DE SUSTRATO'),
  (N'NV-1002', N'CALCE DE IMPRESIÓN'), (N'NV-1003', N'MALLA CON PUNTOS DE EMULSION'), (N'NV-1003', N'ROTURA DE MALLA'),
  (N'NV-1004', N'TEMPERATURA DE FOLIA'), (N'NV-1004', N'ANCLAJE DE FOLIA')) d(nv, defecto) ON d.nv = r.nv_faret;

-- Otros módulos con datos (INNPACK y pallet Faret)
INSERT INTO dbo.procesos (nombre, activo) VALUES (N'Corrugado', 1), (N'Troquelado', 1);
INSERT INTO dbo.maquinas (proceso_id, nombre, codigo_qr, activo) SELECT id, N'MAQ ' + nombre, N'MAQ-TEST-' + nombre, 1 FROM dbo.procesos;
INSERT INTO dbo.usuarios (codigo_usuario, nombre_completo, rol, activo) VALUES (N'CAL-TEST1', N'Inspector Test 1', N'operador', 1), (N'CAL-TEST2', N'Inspector Test 2', N'operador', 1);
INSERT INTO dbo.calidad_faret_pallet_preguntas (texto, orden, activo) VALUES (N'¿Pallet íntegro?', 1, 1);
INSERT INTO dbo.registros_calidad_faret_pallet (tipo_material, dimension, numero_pallet, area_control, operador, fecha_registro, hora_registro)
VALUES (N'NV', N'1000x700', N'P-1', N'13-CORTE Y DIMENSIONADO', N'JUAN PLAZA', '2026-10-07', '09:00:00');
INSERT INTO dbo.registro_calidad_faret_pallet_respuestas (registro_id, pregunta_id, resultado)
SELECT TOP 1 r.id, p.id, N'CUMPLE' FROM dbo.registros_calidad_faret_pallet r CROSS JOIN dbo.calidad_faret_pallet_preguntas p;
PRINT N'PASS  setup: usuario de la app + histórico de ejemplo';
