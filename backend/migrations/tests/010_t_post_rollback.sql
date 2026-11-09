-- Tras el rollback: los respaldos bak010_* deben contener EXACTAMENTE lo que había (catálogo, auditoría y foto de id_evento/criticidad),
-- las columnas/objetos de la 010 deben haber desaparecido y las inspecciones deben conservar su texto de defecto.
SET NOCOUNT ON;
DECLARE @s NVARCHAR(14) = (SELECT TOP 1 SUBSTRING(name, 8, 14) FROM sys.tables WHERE name LIKE N'bak010[_]%[_]eventos' ORDER BY name DESC);
IF @s IS NULL THROW 59600, N'FAIL  no se creó el respaldo bak010_*_eventos', 1;
DECLARE @sql NVARCHAR(MAX), @n INT;
DECLARE @pares TABLE (pre SYSNAME, bak SYSNAME);
INSERT INTO @pares VALUES (N'zz_pre_areas', N'bak010_' + @s + N'_areas'), (N'zz_pre_eventos', N'bak010_' + @s + N'_eventos'),
                          (N'zz_pre_auditoria', N'bak010_' + @s + N'_auditoria'), (N'zz_pre_defectos_evento', N'bak010_' + @s + N'_defectos_evento');
DECLARE @pre SYSNAME, @bak SYSNAME;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT pre, bak FROM @pares;
OPEN c; FETCH NEXT FROM c INTO @pre, @bak;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'SELECT @n = (SELECT COUNT(*) FROM (SELECT * FROM dbo.' + @pre + N' EXCEPT SELECT * FROM dbo.' + @bak + N') a)
                          + (SELECT COUNT(*) FROM (SELECT * FROM dbo.' + @bak + N' EXCEPT SELECT * FROM dbo.' + @pre + N') b)
                          + ABS((SELECT COUNT(*) FROM dbo.' + @pre + N') - (SELECT COUNT(*) FROM dbo.' + @bak + N'))';
    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
    IF @n <> 0 THROW 59601, N'FAIL  un respaldo no coincide con lo que había antes del rollback', 1;
    PRINT N'PASS  respaldo ' + @bak + N' idéntico al original';
    FETCH NEXT FROM c INTO @pre, @bak;
END
CLOSE c; DEALLOCATE c;

SET @sql = N'SELECT @n = COUNT(*) FROM dbo.bak010_' + @s + N'_eventos'; EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
IF @n <> 57 THROW 59602, N'FAIL  el respaldo debe tener los 57 eventos', 1;
SET @sql = N'SELECT @n = COUNT(*) FROM dbo.bak010_' + @s + N'_defectos_evento'; EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @n OUTPUT;
IF @n <> 2 THROW 59603, N'FAIL  el respaldo debe conservar los 2 defectos con id_evento/criticidad', 1;
PRINT N'PASS  el respaldo conserva 57 eventos, la auditoría y los 2 defectos con id_evento/criticidad';

IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NOT NULL OR COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') IS NOT NULL
   OR OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NOT NULL
   OR OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria', N'U') IS NOT NULL OR OBJECT_ID(N'dbo.vw_calidad_faret_eventos_operables', N'V') IS NOT NULL
   OR OBJECT_ID(N'dbo.TR_registro_calidad_faret_defectos_evento', N'TR') IS NOT NULL
    THROW 59604, N'FAIL  quedaron objetos de la 010 después del rollback', 1;
PRINT N'PASS  los objetos de la 010 ya no existen';
-- las inspecciones que se registraron con el catálogo conservan su texto de defecto
IF (SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE defecto IN (N'Abolladura de mantilla de impresión o barniz', N'Calce de barniz.')) <> 2
    THROW 59605, N'FAIL  el rollback alteró el texto de defectos registrados con el catálogo nuevo', 1;
PRINT N'PASS  los defectos registrados con el catálogo nuevo conservan su texto (solo se quitan las 2 columnas)';
