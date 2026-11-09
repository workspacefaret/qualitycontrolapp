-- Foto del estado de TODAS las tablas de la base (filas, checksum de contenido y definición de columnas) y del inventario
-- de objetos. Parámetro sqlcmd: FASE (etiqueta de la foto). Para registro_calidad_faret_defectos solo se miden sus columnas
-- ORIGINALES (id, registro_id, defecto): así se demuestra que el histórico no cambió aunque la tabla tenga 2 columnas nuevas.
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.zz_snap', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.zz_snap (fase NVARCHAR(40) NOT NULL, tabla SYSNAME NOT NULL, filas BIGINT NOT NULL, checksum_contenido INT NULL, checksum_columnas INT NULL);
    CREATE TABLE dbo.zz_objetos (fase NVARCHAR(40) NOT NULL, nombre SYSNAME NOT NULL, tipo NVARCHAR(4) NOT NULL);
END
DELETE FROM dbo.zz_snap WHERE fase = N'$(FASE)';
DELETE FROM dbo.zz_objetos WHERE fase = N'$(FASE)';

DECLARE @t SYSNAME, @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.tables WHERE name NOT LIKE N'zz[_]%' AND name NOT LIKE N'bak010[_]%'
      AND name NOT IN (N'calidad_faret_areas', N'calidad_faret_eventos', N'calidad_faret_catalogo_auditoria');
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- columnas medidas = las originales (excluye id_evento/criticidad de la 010 en la tabla de defectos)
    SET @cols = STUFF((SELECT N', ' + QUOTENAME(c.name) FROM sys.columns c WHERE c.object_id = OBJECT_ID(N'dbo.' + @t)
                          AND NOT (@t = N'registro_calidad_faret_defectos' AND c.name IN (N'id_evento', N'criticidad'))
                        ORDER BY c.column_id FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'');   -- sin STRING_AGG (SQL 2017+)
    SET @sql = N'INSERT INTO dbo.zz_snap (fase, tabla, filas, checksum_contenido, checksum_columnas)
                 SELECT N''$(FASE)'', N''' + @t + N''', COUNT_BIG(*), CHECKSUM_AGG(CHECKSUM(' + @cols + N')),
                 (SELECT CHECKSUM_AGG(CHECKSUM(c.name, ty.name, c.max_length, c.is_nullable))
                    FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
                   WHERE c.object_id = OBJECT_ID(N''dbo.' + @t + N''')
                     AND NOT (N''' + @t + N''' = N''registro_calidad_faret_defectos'' AND c.name IN (N''id_evento'', N''criticidad'')))
                 FROM dbo.' + QUOTENAME(@t);
    EXEC (@sql);
    FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
INSERT INTO dbo.zz_objetos (fase, nombre, tipo)
SELECT N'$(FASE)', name, RTRIM(type) FROM sys.objects WHERE is_ms_shipped = 0 AND name NOT LIKE N'zz[_]%' AND name NOT LIKE N'bak010[_]%'
UNION ALL SELECT N'$(FASE)', i.name, N'IX' FROM sys.indexes i JOIN sys.objects o ON o.object_id = i.object_id
 WHERE o.is_ms_shipped = 0 AND i.name IS NOT NULL AND o.name NOT LIKE N'zz[_]%' AND i.is_primary_key = 0 AND i.is_unique_constraint = 0;
SELECT COUNT(*) AS tablas_en_foto FROM dbo.zz_snap WHERE fase = N'$(FASE)';
