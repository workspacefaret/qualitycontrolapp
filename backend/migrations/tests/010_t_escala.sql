-- Lleva la base de PRUEBAS a la escala real verificada en SAP_NEW (2026-11): 4.161 inspecciones y 399 defectos históricos,
-- con client_uuid (migración 009) en las más recientes. Se ejecuta DESPUÉS de 010_t_setup.sql (que deja 6 inspecciones y 8 defectos).
-- Usa nombres de defecto del catálogo ANTERIOR (incluidos los que el Excel retira) y las 8 etiquetas de área reales.
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'%test%' THROW 59001, N'Este script solo corre en una base de pruebas (nombre con "test").', 1;

DECLARE @existentes INT = (SELECT COUNT(*) FROM dbo.registros_calidad_faret);
IF @existentes <> 6 THROW 59002, N'Se esperaba la base recién preparada con 6 inspecciones.', 1;

DECLARE @areas TABLE (n INT, area NVARCHAR(50), maquina NVARCHAR(100), operador NVARCHAR(150));
INSERT INTO @areas VALUES
 (0, N'03-OFFSET', N'XL - 3', N'AXEL CRUZ'), (1, N'03-OFFSET', N'KBA 2', N'DEDIER LEIVA'), (2, N'03-OFFSET', N'XL - 2', N'JUAN PAILLAMAN'),
 (3, N'04-SERIGRAFÍA', N'SAKURAI', N'ALEJANDRO ALBORNOZ'), (4, N'05-FOLIA', N'FOLIA 2', N'JUAN SALDIAS'),
 (5, N'07-TROQUELADO', N'BOBST 104 - 1', N'SERGIO TORO'), (6, N'10-PEGADO', N'DIANA 3', N'LUIS COLOMBO'),
 (7, N'02-LAMINADO', N'SIRYUS', N'JORGE GONZALEZ'), (8, N'12-FOLLETOS', N'FOLLETOS TI 36/4', N'LUIS RAMIREZ'),
 (9, N'13-CORTE Y DIMENSIONADO', N'GUILLOTINA 1 POLAR 137', N'JUAN PLAZA');

;WITH n AS (SELECT TOP (4155) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT INTO dbo.registros_calidad_faret
    (nv_faret, nv_vb_aprobado, area_control, operador, maquina, presenta_defectos, area_defecto, fecha_registro, hora_registro, observaciones, client_uuid, operador_registro)
SELECT N'NV-' + CAST(2000 + n.i AS NVARCHAR(10)), CASE WHEN n.i % 7 = 0 THEN 0 ELSE 1 END, a.area, a.operador, a.maquina,
       CASE WHEN n.i % 10 = 0 THEN 1 ELSE 0 END,                                  -- ~416 con defectos (se usan 391)
       CASE WHEN n.i % 10 = 0 THEN a.area ELSE NULL END,
       DATEADD(DAY, n.i % 120, '2026-07-07'), DATEADD(MINUTE, (n.i * 7) % 1440, CAST('00:00:00' AS TIME(0))),
       CASE WHEN n.i % 25 = 0 THEN N'obs ' + CAST(n.i AS NVARCHAR(10)) ELSE NULL END,
       CASE WHEN n.i > 1155 THEN LOWER(CONVERT(NVARCHAR(36), NEWID())) ELSE NULL END,   -- 3.000 con client_uuid (único filtrado)
       CASE WHEN n.i % 5 = 0 THEN NULL ELSE N'ANDRES' END
FROM n JOIN @areas a ON a.n = n.i % 10;

INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto)
SELECT TOP (391) r.id,
       CHOOSE((r.id % 8) + 1, N'DIFERENCIA DE TONO', N'DEFECTO DE SECADO', N'PROBLEMA DE SUSTRATO', N'CALCE DE IMPRESIÓN',
                              N'ROTURA DE MALLA', N'TEMPERATURA DE FOLIA', N'ARRUGAS', N'MALA ROTULACION')
FROM dbo.registros_calidad_faret r WHERE r.presenta_defectos = 1 AND r.nv_faret >= N'NV-2000' ORDER BY r.id;

DECLARE @r INT = (SELECT COUNT(*) FROM dbo.registros_calidad_faret), @d INT = (SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos),
        @u INT = (SELECT COUNT(client_uuid) FROM dbo.registros_calidad_faret), @du INT = (SELECT COUNT(DISTINCT client_uuid) FROM dbo.registros_calidad_faret);
IF @r <> 4161 OR @d <> 399 OR @u <> 3000 OR @du <> 3000 THROW 59003, N'FAIL  la escala de prueba no quedó en 4161 inspecciones / 399 defectos / 3000 client_uuid únicos', 1;
PRINT N'PASS  escala real: 4161 inspecciones, 399 defectos, 3000 client_uuid únicos';
