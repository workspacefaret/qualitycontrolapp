-- Pruebas de la migración 010 sobre la base de PRUEBAS (LocalDB). Cada prueba imprime PASS o falla con FAIL + THROW.
-- Las pruebas que modifican datos corren dentro de una transacción que se revierte: la base queda como estaba.
-- En los textos de prueba el acento grave ` representa una comilla simple.
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'%test%' THROW 59001, N'Solo en base de pruebas.', 1;
GO
IF OBJECT_ID(N'dbo.zz_esperar_error', N'P') IS NOT NULL DROP PROCEDURE dbo.zz_esperar_error;
IF OBJECT_ID(N'dbo.zz_esperar_ok', N'P') IS NOT NULL DROP PROCEDURE dbo.zz_esperar_ok;
GO
CREATE PROCEDURE dbo.zz_esperar_error @sql NVARCHAR(MAX), @num INT, @nombre NVARCHAR(200) AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT OFF;
    DECLARE @real INT = 0, @msg NVARCHAR(2000) = N'';
    SET @sql = REPLACE(@sql, N'`', N'''');
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        SET @real = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
    END CATCH
    WHILE @@TRANCOUNT > 0 ROLLBACK;
    BEGIN TRY REVERT; END TRY BEGIN CATCH END CATCH
    IF @real = @num PRINT N'PASS  ' + @nombre;
    ELSE
    BEGIN
        DECLARE @m NVARCHAR(2000) = N'FAIL  ' + @nombre + N' (esperaba error ' + CAST(@num AS NVARCHAR(10)) + N', obtuvo ' + CAST(@real AS NVARCHAR(10)) + N': ' + @msg + N')';
        PRINT @m; THROW 59000, @m, 1;
    END
END
GO
CREATE PROCEDURE dbo.zz_esperar_ok @sql NVARCHAR(MAX), @nombre NVARCHAR(200) AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT OFF;
    DECLARE @real INT = 0, @msg NVARCHAR(2000) = N'';
    SET @sql = REPLACE(@sql, N'`', N'''');
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC (@sql);
    END TRY
    BEGIN CATCH
        SET @real = ERROR_NUMBER(); SET @msg = ERROR_MESSAGE();
    END CATCH
    WHILE @@TRANCOUNT > 0 ROLLBACK;
    BEGIN TRY REVERT; END TRY BEGIN CATCH END CATCH
    IF @real = 0 PRINT N'PASS  ' + @nombre;
    ELSE
    BEGIN
        DECLARE @m NVARCHAR(2000) = N'FAIL  ' + @nombre + N' (error inesperado ' + CAST(@real AS NVARCHAR(10)) + N': ' + @msg + N')';
        PRINT @m; THROW 59000, @m, 1;
    END
END
GO
SET NOCOUNT ON;

-- ======================= A. Contenido del catálogo =======================
IF (SELECT COUNT(*) FROM dbo.calidad_faret_areas) <> 8 THROW 59100, N'FAIL  se esperaban 8 áreas', 1;
PRINT N'PASS  A1 8 áreas';
IF (SELECT COUNT(*) FROM dbo.calidad_faret_eventos) <> 57 OR (SELECT COUNT(DISTINCT id_evento) FROM dbo.calidad_faret_eventos) <> 57 THROW 59101, N'FAIL  se esperaban 57 eventos con ID único', 1;
PRINT N'PASS  A2 57 eventos con ID único';
IF (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad_origen = N'Critico') <> 42
   OR (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad_origen = N'Mayor') <> 14
   OR (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad_origen = N'Menor') <> 1
    THROW 59102, N'FAIL  totales por criticidad distintos de 42/14/1', 1;
PRINT N'PASS  A3 criticidades 42 críticos / 14 mayores / 1 menor';
IF EXISTS (SELECT 1 FROM (VALUES (N'LAM',4),(N'OFF',14),(N'SER',7),(N'FOL',7),(N'TRO',7),(N'PEG',8),(N'FLT',4),(N'CYD',6)) v(cod, n)
           WHERE (SELECT COUNT(*) FROM dbo.calidad_faret_eventos e WHERE e.cod_area = v.cod) <> v.n)
    THROW 59103, N'FAIL  cantidad de eventos por área distinta de la hoja Resumen', 1;
PRINT N'PASS  A4 eventos por área (4/14/7/7/7/8/4/6)';
IF EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE criticidad <> criticidad_origen OR defecto COLLATE Latin1_General_BIN2 <> defecto_origen COLLATE Latin1_General_BIN2)
    THROW 59104, N'FAIL  en la carga inicial el valor vigente debe ser igual al de origen', 1;
PRINT N'PASS  A5 vigente = origen tras la carga';
IF (SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria WHERE accion = N'CARGA_INICIAL') <> 65
    THROW 59105, N'FAIL  la auditoría debe tener 65 filas de carga inicial (8 áreas + 57 eventos)', 1;
PRINT N'PASS  A6 auditoría de carga inicial (65)';

-- Los 5 pendientes: idénticos al Excel, inactivos operativamente, bloqueados
IF (SELECT COUNT(*) FROM dbo.calidad_faret_eventos
    WHERE id_evento IN (N'SER-007', N'FOL-007', N'PEG-007', N'PEG-008', N'CYD-003')
      AND estado = N'Inactivo' AND estado_origen = N'Activo' AND requiere_aprobacion = 1 AND aprobacion = N'PENDIENTE'
      AND observacion_origen IS NOT NULL) <> 5
   OR (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE requiere_aprobacion = 1) <> 5
    THROW 59106, N'FAIL  los 5 eventos pendientes no están como corresponde', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N'SER-007' AND defecto_origen COLLATE Latin1_General_BIN2 = N'Pliegos puntos de barniz' AND criticidad_origen = N'Mayor')
   OR NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N'FOL-007' AND defecto_origen COLLATE Latin1_General_BIN2 = N'tipo de folia correcta' AND criticidad_origen = N'Critico')
   OR NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N'PEG-007' AND defecto_origen COLLATE Latin1_General_BIN2 = N'Pegando con lector' AND criticidad_origen = N'Critico')
   OR NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N'PEG-008' AND defecto_origen COLLATE Latin1_General_BIN2 = N'Mezcla' AND criticidad_origen = N'Critico')
   OR NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N'CYD-003' AND defecto_origen COLLATE Latin1_General_BIN2 = N'Formato corresponde' AND criticidad_origen = N'Critico')
    THROW 59107, N'FAIL  texto/criticidad de los 5 pendientes distintos del Excel', 1;
PRINT N'PASS  A7 los 5 pendientes: texto y criticidad exactos del Excel, inactivos y en PENDIENTE';
IF (SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables) <> 52 OR EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento IN (N'SER-007', N'FOL-007', N'PEG-007', N'PEG-008', N'CYD-003'))
    THROW 59108, N'FAIL  la vista de operables debe tener 52 eventos y ninguno de los pendientes', 1;
PRINT N'PASS  A8 vista de operables: 52 (sin los 5 pendientes)';

-- ======================= B. Integridad referencial y restricciones =======================
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`OFF-001`,N`OFF`,N`x`,N`otro`,N`Mayor`,N`Activo`,99,N`otro`,N`Mayor`,N`Activo`,N`t`)', 2627, N'B1 ID de evento duplicado rechazado';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`ZZZ-001`,N`ZZZ`,N`x`,N`otro`,N`Mayor`,N`Activo`,99,N`otro`,N`Mayor`,N`Activo`,N`t`)', 547, N'B2 área inexistente rechazada (FK)';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`OFF-099`,N`OFF`,N`x`,N`nuevo`,N`Alto`,N`Activo`,99,N`nuevo`,N`Mayor`,N`Activo`,N`t`)', 547, N'B3 criticidad fuera de lista rechazada';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`OFF-1`,N`OFF`,N`x`,N`nuevo`,N`Mayor`,N`Activo`,99,N`nuevo`,N`Mayor`,N`Activo`,N`t`)', 547, N'B4 formato de ID inválido rechazado';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`LAM-099`,N`OFF`,N`x`,N`nuevo`,N`Mayor`,N`Activo`,99,N`nuevo`,N`Mayor`,N`Activo`,N`t`)', 547, N'B5 prefijo del ID distinto del área rechazado';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`OFF-099`,N`OFF`,N`x`,N`ABOLLADURA DE MANTILLA DE IMPRESIÓN O BARNIZ`,N`Mayor`,N`Activo`,99,N`x`,N`Mayor`,N`Activo`,N`t`)', 2627, N'B6 defecto repetido en la misma área rechazado (sin distinguir tildes/mayúsculas)';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET id_evento = N`OFF-900` WHERE id_evento = N`OFF-001`', 51040, N'B7 el ID de un evento es inmutable';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET criticidad_origen = N`Menor` WHERE id_evento = N`OFF-001`', 51041, N'B8 criticidad_origen (Excel) inmutable';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET defecto_origen = N`otro texto` WHERE id_evento = N`OFF-001`', 51041, N'B9 defecto_origen (Excel) inmutable';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET observacion_origen = NULL WHERE id_evento = N`PEG-008`', 51041, N'B10 observación original del Excel inmutable';
EXEC dbo.zz_esperar_error N'DELETE FROM dbo.calidad_faret_eventos WHERE id_evento = N`OFF-001`', 51042, N'B11 los eventos no se pueden eliminar (baja lógica)';
EXEC dbo.zz_esperar_error N'DELETE FROM dbo.calidad_faret_areas WHERE cod_area = N`OFF`', 51045, N'B12 las áreas no se pueden eliminar';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_areas SET area_control = N`03-OFFSET 2` WHERE cod_area = N`OFF`', 51044, N'B13 area_control inmutable';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET estado = N`Activo` WHERE id_evento = N`PEG-008`', 547, N'B14 un evento pendiente no se puede activar sin aprobación';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET aprobacion = N`APROBADA`, estado = N`Activo` WHERE id_evento = N`PEG-008`', 547, N'B15 aprobar exige aprobado_por y aprobado_at';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_eventos SET requiere_aprobacion = 0 WHERE id_evento = N`PEG-008`', 547, N'B16 no se puede quitar el requisito de aprobación dejando el estado PENDIENTE';
EXEC dbo.zz_esperar_error N'UPDATE dbo.calidad_faret_catalogo_auditoria SET usuario = N`otro`', 51046, N'B17 la auditoría no se puede modificar';
EXEC dbo.zz_esperar_error N'DELETE FROM dbo.calidad_faret_catalogo_auditoria', 51046, N'B18 la auditoría no se puede borrar';

-- ======================= C. Auditoría y criticidad configurable =======================
EXEC dbo.zz_esperar_ok N'
EXEC sp_set_session_context N`usuario`, N`tester.calidad`;
EXEC sp_set_session_context N`motivo`, N`prueba de auditoria`;
UPDATE dbo.calidad_faret_eventos SET criticidad = N`Critico` WHERE id_evento = N`OFF-006`;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_catalogo_auditoria WHERE clave = N`OFF-006` AND accion = N`MODIFICACION` AND campo = N`criticidad`
               AND valor_anterior = N`Mayor` AND valor_nuevo = N`Critico` AND usuario = N`tester.calidad` AND motivo = N`prueba de auditoria`)
    THROW 59200, N`sin fila de auditoria de criticidad`, 1;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N`OFF-006` AND criticidad = N`Critico` AND criticidad_origen = N`Mayor` AND updated_by = N`tester.calidad` AND updated_at IS NOT NULL)
    THROW 59201, N`la criticidad de origen debe conservarse y updated_by/updated_at registrarse`, 1;
UPDATE dbo.calidad_faret_eventos SET defecto = N`Imagen FANTASMA.` WHERE id_evento = N`OFF-006`;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_catalogo_auditoria WHERE clave = N`OFF-006` AND campo = N`defecto` AND valor_anterior = N`Imagen fantasma.` AND valor_nuevo = N`Imagen FANTASMA.`)
    THROW 59202, N`un cambio solo de mayusculas tambien debe auditarse`, 1;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N`OFF-006` AND defecto_origen = N`Imagen fantasma.`) THROW 59203, N`defecto_origen debe conservar el texto del Excel`, 1;
', N'C1 cambio de criticidad/descripción: auditado (quién, motivo, antes/después) y el origen del Excel se conserva';
EXEC dbo.zz_esperar_ok N'
UPDATE dbo.calidad_faret_eventos SET estado = N`Inactivo` WHERE id_evento = N`OFF-001`;
IF EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento = N`OFF-001`) THROW 59210, N`un evento inactivo no debe ser operable`, 1;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N`OFF-001`) THROW 59211, N`la baja es logica: la fila debe seguir existiendo`, 1;
UPDATE dbo.calidad_faret_areas SET estado = N`Inactivo` WHERE cod_area = N`LAM`;
IF EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables WHERE cod_area = N`LAM`) THROW 59212, N`un area inactiva no debe ofrecer eventos`, 1;
', N'C2 baja lógica de evento y de área: dejan de ser operables sin borrar nada';

-- ======================= D. Uso desde la cuenta de la app (permisos reales) =======================
EXEC dbo.zz_esperar_ok N'
EXECUTE AS USER = N`quality_control_backend_sql`;
IF (SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables) <> 52 THROW 59300, N`la cuenta de la app debe poder leer la vista`, 1;
IF (SELECT COUNT(*) FROM dbo.calidad_faret_eventos) <> 57 OR (SELECT COUNT(*) FROM dbo.calidad_faret_areas) <> 8 THROW 59301, N`la cuenta de la app debe poder leer las tablas`, 1;
REVERT;', N'D1 la cuenta de la app lee el catálogo (GRANT SELECT mínimo)';
EXEC dbo.zz_esperar_ok N'
EXECUTE AS USER = N`quality_control_backend_sql`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad)
SELECT id, N`Abolladura de mantilla de impresión o barniz.`, N`OFF-001`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;
REVERT;', N'D2 defecto con evento válido, operable y del área del registro: aceptado';
EXEC dbo.zz_esperar_ok N'
EXECUTE AS USER = N`quality_control_backend_sql`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto)
SELECT id, N`DEFECTO DE SECADO` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;
REVERT;', N'D3 cliente antiguo (texto sin id_evento, incluso de un defecto retirado): sigue aceptado como hoy';
EXEC dbo.zz_esperar_error N'
EXECUTE AS USER = N`quality_control_backend_sql`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad)
SELECT id, N`Calce de barniz.`, N`SER-001`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;', 51031, N'D4 evento de OTRA área (serigrafía en un registro de offset) rechazado';
EXEC dbo.zz_esperar_error N'
EXECUTE AS USER = N`quality_control_backend_sql`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad)
SELECT id, N`Pliegos puntos de barniz`, N`SER-007`, N`Mayor` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1003`;', 51030, N'D5 SER-007 (pendiente de Calidad) no se puede usar';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`tipo de folia correcta`, N`FOL-007`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1004`', 51030, N'D6 FOL-007 (pendiente) no se puede usar ni siquiera con permisos de administrador';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`x`, N`PEG-007`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`', 51030, N'D7 PEG-007 (pendiente) no se puede usar';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`x`, N`PEG-008`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`', 51030, N'D8 PEG-008 (pendiente) no se puede usar';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`x`, N`CYD-003`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1006`', 51030, N'D9 CYD-003 (pendiente) no se puede usar';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`x`, N`OFF-999`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`', 547, N'D10 evento inexistente rechazado (FK)';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento) SELECT id, N`x`, N`OFF-001` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`', 547, N'D11 id_evento sin criticidad congelada rechazado';
EXEC dbo.zz_esperar_error N'INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, criticidad) SELECT id, N`x`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`', 547, N'D12 criticidad sin id_evento rechazada';
EXEC dbo.zz_esperar_error N'
UPDATE dbo.calidad_faret_eventos SET estado = N`Inactivo` WHERE id_evento = N`OFF-001`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`x`, N`OFF-001`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;', 51030, N'D13 evento dado de baja (inactivo) ya no se puede registrar';

-- Aprobación de Calidad: con aprobación, activación y misma área, el evento pasa a ser utilizable (y queda auditado)
EXEC dbo.zz_esperar_ok N'
EXEC sp_set_session_context N`usuario`, N`dba`;
EXEC sp_set_session_context N`motivo`, N`aprobacion de Calidad (prueba)`;
UPDATE dbo.calidad_faret_eventos SET aprobacion = N`APROBADA`, aprobado_por = N`Calidad`, aprobado_at = GETDATE(), aprobacion_ref = N`correo prueba`, estado = N`Activo` WHERE id_evento = N`SER-007`;
IF NOT EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables WHERE id_evento = N`SER-007`) THROW 59320, N`aprobado y activo debe ser operable`, 1;
IF (SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria WHERE clave = N`SER-007` AND accion = N`MODIFICACION` AND campo IN (N`estado`, N`aprobacion`, N`aprobacion_ref`)) <> 3 THROW 59321, N`la aprobacion debe quedar auditada (estado, aprobacion, aprobacion_ref)`, 1;
IF NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos WHERE id_evento = N`SER-007` AND estado_origen = N`Activo` AND observacion_origen IS NOT NULL AND defecto_origen = N`Pliegos puntos de barniz`) THROW 59322, N`el estado y la observacion originales del Excel deben conservarse`, 1;
EXECUTE AS USER = N`quality_control_backend_sql`;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`Pliegos puntos de barniz`, N`SER-007`, N`Mayor` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1003`;
REVERT;', N'D14 tras la aprobación expresa de Calidad el evento SER-007 se puede usar; origen del Excel intacto';

-- Criticidad histórica congelada
EXEC dbo.zz_esperar_ok N'
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`Imagen fantasma.`, N`OFF-006`, N`Mayor` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;
UPDATE dbo.calidad_faret_eventos SET criticidad = N`Critico` WHERE id_evento = N`OFF-006`;
IF NOT EXISTS (SELECT 1 FROM dbo.registro_calidad_faret_defectos WHERE id_evento = N`OFF-006` AND criticidad = N`Mayor`) THROW 59330, N`la criticidad de la inspeccion cambio al modificar el catalogo`, 1;
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`Imagen fantasma.`, N`OFF-006`, N`Critico` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1002`;
IF (SELECT COUNT(DISTINCT criticidad) FROM dbo.registro_calidad_faret_defectos WHERE id_evento = N`OFF-006`) <> 2 THROW 59331, N`deben coexistir la criticidad antigua y la nueva`, 1;
', N'D15 cambio posterior de criticidad: lo registrado antes conserva la suya, lo nuevo usa la vigente';
EXEC dbo.zz_esperar_error N'
INSERT INTO dbo.registro_calidad_faret_defectos (registro_id, defecto, id_evento, criticidad) SELECT id, N`Imagen fantasma.`, N`OFF-006`, N`Mayor` FROM dbo.registros_calidad_faret WHERE nv_faret = N`NV-1001`;
UPDATE dbo.registro_calidad_faret_defectos SET criticidad = N`Critico` WHERE id_evento = N`OFF-006`;', 51032, N'D16 la criticidad guardada en una inspección no se puede alterar';
EXEC dbo.zz_esperar_ok N'UPDATE dbo.registro_calidad_faret_defectos SET defecto = defecto WHERE id_evento IS NULL', N'D17 el trigger no interfiere con actualizaciones de filas históricas (id_evento NULL)';

-- ======================= E. Permisos mínimos de la cuenta de la app =======================
EXEC dbo.zz_esperar_error N'EXECUTE AS USER = N`quality_control_backend_sql`; INSERT INTO dbo.calidad_faret_eventos (id_evento,cod_area,tipo_registro,defecto,criticidad,estado,orden,defecto_origen,criticidad_origen,estado_origen,texto_documento) VALUES (N`OFF-099`,N`OFF`,N`x`,N`n`,N`Mayor`,N`Activo`,99,N`n`,N`Mayor`,N`Activo`,N`t`);', 229, N'E1 la app NO puede insertar en el catálogo';
EXEC dbo.zz_esperar_error N'EXECUTE AS USER = N`quality_control_backend_sql`; UPDATE dbo.calidad_faret_eventos SET criticidad = N`Menor`;', 229, N'E2 la app NO puede modificar el catálogo';
EXEC dbo.zz_esperar_error N'EXECUTE AS USER = N`quality_control_backend_sql`; DELETE FROM dbo.calidad_faret_areas;', 229, N'E3 la app NO puede borrar áreas';
EXEC dbo.zz_esperar_error N'EXECUTE AS USER = N`quality_control_backend_sql`; SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria;', 229, N'E4 la app NO puede leer la auditoría';
EXEC dbo.zz_esperar_error N'EXECUTE AS USER = N`quality_control_backend_sql`; UPDATE dbo.registro_calidad_faret_defectos SET criticidad = N`Menor`;', 229, N'E5 la app NO puede modificar defectos ya registrados';
DECLARE @perm INT = (SELECT COUNT(*) FROM sys.database_permissions p
                     WHERE p.grantee_principal_id = USER_ID(N'quality_control_backend_sql')
                       AND p.class = 1 AND OBJECT_NAME(p.major_id) IN (N'calidad_faret_areas', N'calidad_faret_eventos', N'vw_calidad_faret_eventos_operables', N'calidad_faret_catalogo_auditoria')
                       AND p.permission_name <> N'SELECT');
IF @perm <> 0 THROW 59400, N'FAIL  la cuenta de la app tiene permisos distintos de SELECT sobre objetos nuevos', 1;
IF (SELECT COUNT(*) FROM sys.database_permissions p WHERE p.grantee_principal_id = USER_ID(N'quality_control_backend_sql') AND p.class = 1
      AND OBJECT_NAME(p.major_id) IN (N'calidad_faret_areas', N'calidad_faret_eventos', N'vw_calidad_faret_eventos_operables') AND p.permission_name = N'SELECT' AND p.state = N'G') <> 3
    THROW 59401, N'FAIL  se esperaban exactamente 3 GRANT SELECT (2 tablas + vista)', 1;
PRINT N'PASS  E6 permisos nuevos de la app: exactamente 3 GRANT SELECT y ningún otro';
PRINT N'PASS  === pruebas de catálogo terminadas ===';
