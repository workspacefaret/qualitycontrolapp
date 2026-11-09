-- Compara dos fotos (010_t_snapshot.sql): $(FASE_A) = referencia, $(FASE_B) = actual.
--  * Toda tabla preexistente debe conservar filas, contenido (checksum) y definición de columnas -> histórico y otros módulos intactos.
--  * Parámetro TABLAS=1 compara filas/contenido/columnas de las tablas; TABLAS=0 omite esa parte.
--  * Inventario de objetos: MODO=igual  -> idéntico a la referencia (p. ej. tras un rollback)
--                           MODO=aditiva -> solo aparecen objetos propios de la 010 y no desaparece ninguno preexistente
--                           MODO=ninguno -> no compara objetos.
SET NOCOUNT ON;
DECLARE @malas INT = CASE WHEN N'$(TABLAS)' <> N'1' THEN 0 ELSE (
    SELECT COUNT(*) FROM dbo.zz_snap a
    LEFT JOIN dbo.zz_snap b ON b.fase = N'$(FASE_B)' AND b.tabla = a.tabla
    WHERE a.fase = N'$(FASE_A)'
      AND (b.tabla IS NULL OR a.filas <> b.filas OR ISNULL(a.checksum_contenido, 0) <> ISNULL(b.checksum_contenido, 0)
           OR ISNULL(a.checksum_columnas, 0) <> ISNULL(b.checksum_columnas, 0))) END;
IF @malas <> 0
BEGIN
    SELECT a.tabla, a.filas AS filas_ref, b.filas AS filas_actual, a.checksum_contenido AS chk_ref, b.checksum_contenido AS chk_actual,
           a.checksum_columnas AS cols_ref, b.checksum_columnas AS cols_actual
    FROM dbo.zz_snap a LEFT JOIN dbo.zz_snap b ON b.fase = N'$(FASE_B)' AND b.tabla = a.tabla
    WHERE a.fase = N'$(FASE_A)' AND (b.tabla IS NULL OR a.filas <> b.filas OR ISNULL(a.checksum_contenido, 0) <> ISNULL(b.checksum_contenido, 0) OR ISNULL(a.checksum_columnas, 0) <> ISNULL(b.checksum_columnas, 0));
    THROW 59500, N'FAIL  hay tablas preexistentes con contenido o definición distintos', 1;
END
DECLARE @tablas INT = (SELECT COUNT(*) FROM dbo.zz_snap WHERE fase = N'$(FASE_A)');
DECLARE @filas BIGINT = (SELECT SUM(filas) FROM dbo.zz_snap WHERE fase = N'$(FASE_A)');
IF N'$(TABLAS)' = N'1' PRINT N'PASS  ' + CAST(@tablas AS NVARCHAR(10)) + N' tablas preexistentes idénticas (filas, contenido y columnas; ' + CAST(@filas AS NVARCHAR(20)) + N' filas en total)';

IF N'$(MODO)' = N'ninguno' RETURN;
DECLARE @desaparecen INT = (SELECT COUNT(*) FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)') x);
IF @desaparecen <> 0
BEGIN
    SELECT nombre, tipo, N'desaparece' AS estado FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)') x;
    THROW 59501, N'FAIL  desapareció algún objeto preexistente', 1;
END
DECLARE @nuevos INT = (SELECT COUNT(*) FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)') x);
IF N'$(MODO)' = N'igual'
BEGIN
    IF @nuevos <> 0
    BEGIN
        SELECT nombre, tipo, N'sobra' AS estado FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)') x;
        THROW 59502, N'FAIL  quedaron objetos que no existían en la referencia', 1;
    END
    PRINT N'PASS  inventario de objetos idéntico al de la referencia (sin objetos residuales)';
END
ELSE
BEGIN
    DECLARE @ajenos INT = (SELECT COUNT(*) FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)') x
        WHERE NOT (nombre LIKE N'%calidad_faret_eventos%' OR nombre LIKE N'%calidad_faret_areas%' OR nombre LIKE N'%calidad_faret_catalogo_auditoria%'
                   OR nombre = N'vw_calidad_faret_eventos_operables' OR nombre LIKE N'%registro_calidad_faret_defectos_evento%'
                   OR nombre = N'IX_registro_calidad_faret_defectos_id_evento'));
    IF @ajenos <> 0
    BEGIN
        SELECT nombre, tipo, N'ajeno a la 010' AS estado FROM (SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_B)' EXCEPT SELECT nombre, tipo FROM dbo.zz_objetos WHERE fase = N'$(FASE_A)') x
        WHERE NOT (nombre LIKE N'%calidad_faret_eventos%' OR nombre LIKE N'%calidad_faret_areas%' OR nombre LIKE N'%calidad_faret_catalogo_auditoria%'
                   OR nombre = N'vw_calidad_faret_eventos_operables' OR nombre LIKE N'%registro_calidad_faret_defectos_evento%'
                   OR nombre = N'IX_registro_calidad_faret_defectos_id_evento');
        THROW 59503, N'FAIL  aparecieron objetos que no pertenecen a la 010', 1;
    END
    PRINT N'PASS  la 010 solo agregó ' + CAST(@nuevos AS NVARCHAR(10)) + N' objetos propios (tablas, vista, triggers, restricciones, índices) y no quitó ninguno';
END
