<#
.SYNOPSIS
  Diagnostico de compatibilidad SOLO LECTURA para la migracion 010 (catalogo maestro de eventos de calidad FARET).

.DESCRIPTION
  Se conecta a calidad_db y ejecuta UNICAMENTE consultas SELECT sobre vistas de catalogo (sys.*), metadatos y conteos de las
  tablas de CALIDAD PRODUCCION FARET. No crea, modifica ni borra nada, no cambia permisos y no reinicia servicios.
  Cada consulta pasa por un validador interno que rechaza cualquier sentencia que no sea SELECT/WITH o que contenga palabras
  de escritura (INSERT, UPDATE, DELETE, ALTER, CREATE, DROP, EXEC, GRANT, INTO, etc.); la conexion usa aislamiento READ UNCOMMITTED
  y LOCK_TIMEOUT corto, de modo que no bloquea las inspecciones en curso.

  Ejecutar en SRV-API o donde corresponda, con una cuenta con permisos de lectura de metadatos (la misma cuenta con DDL que
  luego ejecutara la migracion es lo ideal, porque tambien permite comprobar que tiene los permisos necesarios).

  NO guarda ni imprime contrasenas: con -Autenticacion Sql la clave se pide de forma segura (SecureString) y no se escribe a disco.
  El informe generado contiene metadatos y conteos, nunca datos de las inspecciones (ni textos de observaciones ni nombres de operadores).

.PARAMETER Servidor     Instancia SQL Server (por ejemplo SAP_NEW o 192.168.1.231).
.PARAMETER Base         Base de datos (por defecto calidad_db).
.PARAMETER Autenticacion Windows (por defecto) o Sql.
.PARAMETER Usuario      Usuario SQL (solo con -Autenticacion Sql).
.PARAMETER Salida       Carpeta donde dejar el informe (.txt y .json). Por defecto, la carpeta actual.
.PARAMETER ConfiarCertificado  Acepta el certificado del servidor (si es autofirmado).
.PARAMETER UsuarioApp   Cuenta de la aplicacion cuyos permisos se revisan (por defecto quality_control_backend_sql).

.EXAMPLE
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [string]$Salida,
    [switch]$ConfiarCertificado,
    [string]$UsuarioApp = 'quality_control_backend_sql'
)

$ErrorActionPreference = 'Stop'
if (-not $Salida) { $Salida = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'salida' }
Add-Type -AssemblyName System.Data

# ------------------------------------------------------------------------------------------------
# Conexion (solo lectura)
# ------------------------------------------------------------------------------------------------
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Data Source'] = $Servidor
$csb['Initial Catalog'] = $Base
$csb['Connect Timeout'] = 15
if ($ConfiarCertificado) { $csb['TrustServerCertificate'] = $true }
$conexion = $null
if ($Autenticacion -eq 'Windows') {
    $csb['Integrated Security'] = $true
    $conexion = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString)
} else {
    if (-not $Usuario) { throw 'Con -Autenticacion Sql debe indicar -Usuario.' }
    $clave = Read-Host -AsSecureString -Prompt "Clave de $Usuario (no se muestra ni se guarda)"
    $clave.MakeReadOnly()
    $cred = New-Object System.Data.SqlClient.SqlCredential($Usuario, $clave)
    $conexion = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString, $cred)
}
$conexion.Open()

# Parametros de sesion constantes (no provienen de ninguna consulta del diagnostico)
foreach ($set in @('SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED', 'SET LOCK_TIMEOUT 5000', 'SET NOCOUNT ON')) {
    $c = $conexion.CreateCommand(); $c.CommandText = $set; [void]$c.ExecuteNonQuery()
}

$prohibidas = '\b(INSERT|UPDATE|DELETE|MERGE|ALTER|CREATE|DROP|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|DENY|BACKUP|RESTORE|SHUTDOWN|KILL|RECONFIGURE|INTO|OPENROWSET|OPENQUERY|XP_CMDSHELL)\b'

function Test-SoloLectura([string]$sql) {
    # Quita comentarios y literales de texto antes de buscar palabras de escritura
    $limpio = [regex]::Replace($sql, "'([^']|'')*'", "''")
    $limpio = [regex]::Replace($limpio, '--[^\r\n]*', ' ')
    $limpio = [regex]::Replace($limpio, '/\*.*?\*/', ' ', 'Singleline')
    if ($limpio.TrimStart() -notmatch '^(?i)(SELECT|WITH)\b') { return $false }
    if ($limpio -match "(?i)$prohibidas") { return $false }
    if ($limpio.Contains(';')) { return $false }
    return $true
}

$resultados = [ordered]@{}
$fallos = New-Object System.Collections.ArrayList

function Invoke-Consulta([string]$clave, [string]$sql, [hashtable]$parametros = @{}) {
    if (-not (Test-SoloLectura $sql)) { throw "Consulta '$clave' rechazada por el validador de solo lectura." }
    try {
        $cmd = $conexion.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.CommandTimeout = 30
        foreach ($k in $parametros.Keys) { [void]$cmd.Parameters.AddWithValue($k, $parametros[$k]) }
        $dt = New-Object System.Data.DataTable
        $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        [void]$da.Fill($dt)
        $filas = @()
        foreach ($r in $dt.Rows) {
            $o = [ordered]@{}
            foreach ($col in $dt.Columns) { $v = $r[$col.ColumnName]; if ($v -is [System.DBNull]) { $v = $null }; $o[$col.ColumnName] = $v }
            $filas += [pscustomobject]$o
        }
        $resultados[$clave] = $filas
        return $filas
    } catch {
        [void]$fallos.Add([pscustomobject]@{ consulta = $clave; error = $_.Exception.Message })
        $resultados[$clave] = $null
        return $null
    }
}

# ------------------------------------------------------------------------------------------------
# Consultas (todas SELECT sobre catalogo/metadatos o conteos agregados)
# ------------------------------------------------------------------------------------------------
$tablasFaret = "'registros_calidad_faret','registro_calidad_faret_defectos','registro_calidad_faret_adjuntos','registros_calidad_faret_pallet','registro_calidad_faret_pallet_respuestas','calidad_faret_operadores','calidad_faret_pallet_preguntas'"
$tablasCore = "'registros_calidad_faret','registro_calidad_faret_defectos'"

$q = [ordered]@{}
$q['servidor'] = @"
SELECT @@SERVERNAME AS servidor, CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(40)) AS version,
       CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(40)) AS nivel, CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100)) AS edicion,
       CAST(SERVERPROPERTY('ProductUpdateLevel') AS NVARCHAR(40)) AS actualizacion,
       d.name AS base, d.compatibility_level AS nivel_compatibilidad, d.collation_name AS colacion, d.state_desc AS estado,
       d.user_access_desc AS acceso, d.is_read_only AS solo_lectura, d.recovery_model_desc AS modelo_recuperacion,
       d.is_read_committed_snapshot_on AS rcsi, d.snapshot_isolation_state_desc AS aislamiento_snapshot,
       d.is_trustworthy_on AS trustworthy, SUSER_SNAME() AS cuenta_diagnostico
FROM sys.databases d WHERE d.name = DB_NAME()
"@
$q['columnas'] = @"
SELECT t.name AS tabla, c.column_id AS pos, c.name AS columna, ty.name AS tipo, c.max_length, c.precision, c.scale,
       c.is_nullable, c.is_identity, c.is_computed, c.collation_name
FROM sys.tables t JOIN sys.columns c ON c.object_id = t.object_id JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN ($tablasFaret) ORDER BY t.name, c.column_id
"@
$q['indices'] = @"
SELECT t.name AS tabla, i.name AS indice, i.type_desc AS tipo, i.is_unique, i.is_primary_key AS es_pk, i.is_unique_constraint AS es_uq,
       i.is_disabled, i.filter_definition AS filtro,
       STUFF((SELECT ', ' + c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
              WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0 ORDER BY ic.key_ordinal
              FOR XML PATH('')), 1, 2, '') AS columnas
FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
WHERE t.name IN ($tablasFaret) AND i.type > 0 ORDER BY t.name, i.index_id
"@
$q['claves_foraneas'] = @"
SELECT fk.name AS clave_foranea, OBJECT_NAME(fk.parent_object_id) AS tabla_hija, OBJECT_NAME(fk.referenced_object_id) AS tabla_padre,
       fk.is_disabled, fk.delete_referential_action_desc AS al_borrar
FROM sys.foreign_keys fk
WHERE OBJECT_NAME(fk.parent_object_id) IN ($tablasFaret) OR OBJECT_NAME(fk.referenced_object_id) IN ($tablasFaret)
"@
$q['restricciones'] = @"
SELECT OBJECT_NAME(cc.parent_object_id) AS tabla, cc.name AS restriccion, 'CHECK' AS tipo, cc.definition, cc.is_disabled
FROM sys.check_constraints cc WHERE OBJECT_NAME(cc.parent_object_id) IN ($tablasFaret)
UNION ALL
SELECT OBJECT_NAME(dc.parent_object_id), dc.name, 'DEFAULT', dc.definition, 0
FROM sys.default_constraints dc WHERE OBJECT_NAME(dc.parent_object_id) IN ($tablasFaret)
"@
$q['triggers'] = @"
SELECT tr.name AS trigger_nombre, CASE tr.parent_class WHEN 0 THEN '(nivel base de datos)' ELSE OBJECT_NAME(tr.parent_id) END AS tabla,
       tr.is_disabled, tr.is_instead_of_trigger AS instead_of
FROM sys.triggers tr WHERE tr.parent_class = 0 OR OBJECT_NAME(tr.parent_id) IN ($tablasFaret)
"@
$q['dependencias'] = @"
SELECT DISTINCT OBJECT_NAME(d.referencing_id) AS objeto, o.type_desc AS tipo, d.referenced_entity_name AS referencia,
       d.is_schema_bound_reference AS schemabound
FROM sys.sql_expression_dependencies d JOIN sys.objects o ON o.object_id = d.referencing_id
WHERE d.referenced_entity_name IN ($tablasCore) AND d.referencing_id <> d.referenced_id   -- excluye autorreferencias de la propia tabla
"@
$q['modulos'] = @"
SELECT OBJECT_NAME(m.object_id) AS objeto, o.type_desc AS tipo, m.is_schema_bound AS schemabound,
       CASE WHEN m.definition LIKE '%select *%' OR m.definition LIKE '%.*%' THEN 1 ELSE 0 END AS usa_select_estrella,
       CASE WHEN m.definition LIKE '%insert%registro_calidad_faret_defectos%values%' OR m.definition LIKE '%insert%registro_calidad_faret_defectos%select%' THEN 1 ELSE 0 END AS inserta_en_defectos,
       CASE WHEN m.definition IS NULL THEN 1 ELSE 0 END AS definicion_oculta
FROM sys.sql_modules m JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.is_ms_shipped = 0 AND (m.definition LIKE '%registro_calidad_faret_defectos%' OR m.definition LIKE '%registros_calidad_faret%')
"@
$q['permisos_app'] = @"
SELECT pr.name AS principal, p.class_desc AS clase, OBJECT_NAME(p.major_id) AS objeto, c.name AS columna, p.permission_name AS permiso, p.state_desc AS estado
FROM sys.database_permissions p JOIN sys.database_principals pr ON pr.principal_id = p.grantee_principal_id
LEFT JOIN sys.columns c ON c.object_id = p.major_id AND c.column_id = p.minor_id AND p.minor_id > 0
WHERE pr.name = @usuarioApp AND (p.class = 0 OR OBJECT_NAME(p.major_id) IN ($tablasFaret))
ORDER BY OBJECT_NAME(p.major_id), p.permission_name
"@
$q['roles_app'] = @"
SELECT u.name AS usuario, r.name AS rol FROM sys.database_role_members m
JOIN sys.database_principals r ON r.principal_id = m.role_principal_id JOIN sys.database_principals u ON u.principal_id = m.member_principal_id
WHERE u.name = @usuarioApp
"@
$q['usuario_app'] = "SELECT COUNT(*) AS existe FROM sys.database_principals WHERE name = @usuarioApp"
$q['permisos_ejecutor'] = @"
SELECT IS_MEMBER('db_owner') AS db_owner, IS_SRVROLEMEMBER('sysadmin') AS sysadmin,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CREATE TABLE') AS crear_tabla,
       HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CREATE VIEW') AS crear_vista,
       HAS_PERMS_BY_NAME('dbo', 'SCHEMA', 'ALTER') AS alter_esquema_dbo,
       HAS_PERMS_BY_NAME('dbo.registro_calidad_faret_defectos', 'OBJECT', 'ALTER') AS alter_defectos,
       HAS_PERMS_BY_NAME('dbo.registro_calidad_faret_defectos', 'OBJECT', 'CONTROL') AS control_defectos
"@
$q['caracteristicas_tabla'] = @"
SELECT t.name AS tabla, t.is_memory_optimized, t.temporal_type, t.is_tracked_by_cdc, t.is_replicated, t.is_merge_published,
       t.is_filetable, t.lock_escalation_desc AS escalado_bloqueo,
       CASE WHEN EXISTS (SELECT 1 FROM sys.change_tracking_tables ct WHERE ct.object_id = t.object_id) THEN 1 ELSE 0 END AS change_tracking
FROM sys.tables t WHERE t.name IN ($tablasFaret)
"@
$q['colisiones_010'] = @"
SELECT o.name AS nombre, o.type_desc AS tipo, 'objeto' AS donde FROM sys.objects o
WHERE o.name IN ('calidad_faret_areas','calidad_faret_eventos','calidad_faret_catalogo_auditoria','vw_calidad_faret_eventos_operables',
                 'TR_registro_calidad_faret_defectos_evento','TR_calidad_faret_eventos_upd','TR_calidad_faret_eventos_del',
                 'TR_calidad_faret_areas_upd','TR_calidad_faret_areas_del','TR_calidad_faret_catalogo_auditoria_inmutable',
                 'FK_registro_calidad_faret_defectos_evento','CK_registro_calidad_faret_defectos_evento_crit',
                 'PK_calidad_faret_areas','PK_calidad_faret_eventos','PK_calidad_faret_catalogo_auditoria',
                 'UQ_calidad_faret_areas_area_control','UQ_calidad_faret_eventos_area_defecto','FK_calidad_faret_eventos_area')
   OR o.name LIKE 'CK[_]calidad[_]faret[_]areas[_]%' OR o.name LIKE 'CK[_]calidad[_]faret[_]eventos[_]%'
   OR o.name LIKE 'CK[_]calidad[_]faret[_]catalogo[_]auditoria[_]%' OR o.name LIKE 'DF[_]calidad[_]faret[_]areas[_]%'
   OR o.name LIKE 'DF[_]calidad[_]faret[_]eventos[_]%' OR o.name LIKE 'DF[_]calidad[_]faret[_]catalogo[_]auditoria[_]%'
   OR o.name LIKE 'bak010[_]%'
UNION ALL
SELECT i.name, 'INDEX', 'indice' FROM sys.indexes i
WHERE i.name IN ('IX_calidad_faret_catalogo_auditoria_clave','IX_registro_calidad_faret_defectos_id_evento')
UNION ALL
SELECT c.name, 'COLUMN en defectos', 'columna' FROM sys.columns c
WHERE c.object_id = OBJECT_ID('dbo.registro_calidad_faret_defectos') AND c.name IN ('id_evento','criticidad')
"@
$q['volumen_registros'] = @"
SELECT COUNT_BIG(*) AS filas, MIN(fecha_registro) AS desde, MAX(fecha_registro) AS hasta,
       SUM(CASE WHEN eliminado = 1 THEN 1 ELSE 0 END) AS eliminados,
       SUM(CASE WHEN presenta_defectos = 1 THEN 1 ELSE 0 END) AS con_defectos,
       SUM(CASE WHEN presenta_defectos = 1 AND (area_defecto IS NULL OR area_defecto = '') THEN 1 ELSE 0 END) AS con_defectos_sin_area_defecto
FROM dbo.registros_calidad_faret
"@
$q['volumen_defectos'] = @"
SELECT COUNT_BIG(*) AS filas, MAX(LEN(defecto)) AS largo_maximo, COUNT(DISTINCT defecto) AS textos_distintos
FROM dbo.registro_calidad_faret_defectos
"@
$q['areas_control'] = "SELECT area_control, COUNT_BIG(*) AS filas FROM dbo.registros_calidad_faret GROUP BY area_control ORDER BY 2 DESC"
$q['areas_defecto'] = "SELECT area_defecto, COUNT_BIG(*) AS filas FROM dbo.registros_calidad_faret WHERE presenta_defectos = 1 GROUP BY area_defecto ORDER BY 2 DESC"
$q['actividad_por_hora_30d'] = @"
SELECT DATEPART(HOUR, hora_registro) AS hora, COUNT_BIG(*) AS inspecciones
FROM dbo.registros_calidad_faret WHERE fecha_registro >= DATEADD(DAY, -30, CAST(GETDATE() AS DATE))
GROUP BY DATEPART(HOUR, hora_registro) ORDER BY 1
"@
$q['actividad_14d'] = @"
SELECT fecha_registro AS fecha, COUNT_BIG(*) AS inspecciones FROM dbo.registros_calidad_faret
WHERE fecha_registro >= DATEADD(DAY, -14, CAST(GETDATE() AS DATE)) GROUP BY fecha_registro ORDER BY 1 DESC
"@
$q['tamano_tablas'] = @"
SELECT t.name AS tabla, CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS DECIMAL(12,2)) AS mb_reservados,
       SUM(CASE WHEN ps.index_id < 2 THEN ps.row_count ELSE 0 END) AS filas
FROM sys.dm_db_partition_stats ps JOIN sys.tables t ON t.object_id = ps.object_id WHERE t.name IN ($tablasFaret) GROUP BY t.name
"@
$q['respaldos'] = @"
SELECT TOP 6 bs.type AS tipo, bs.backup_finish_date AS fin, CAST(bs.backup_size / 1048576.0 AS DECIMAL(14,1)) AS mb
FROM msdb.dbo.backupset bs WHERE bs.database_name = DB_NAME() ORDER BY bs.backup_finish_date DESC
"@

foreach ($k in $q.Keys) {
    $p = @{}
    if ($q[$k] -match '@usuarioApp') { $p['@usuarioApp'] = $UsuarioApp }
    [void](Invoke-Consulta $k $q[$k] $p)
}
# (la conexion se mantiene abierta hasta el final del script)

# ------------------------------------------------------------------------------------------------
# Matriz de compatibilidad
# ------------------------------------------------------------------------------------------------
$matriz = New-Object System.Collections.ArrayList
function Add-Chequeo([string]$id, [string]$tema, [string]$estado, [string]$detalle) {
    [void]$matriz.Add([pscustomobject]@{ id = $id; tema = $tema; estado = $estado; detalle = $detalle })
}
function Ok($clave) { return ($null -ne $resultados[$clave]) }
function Col($tabla, $columna) { return @($resultados['columnas'] | Where-Object { $_.tabla -eq $tabla -and $_.columna -eq $columna })[0] }

if (Ok 'servidor') {
    $s = $resultados['servidor'][0]
    $major = [int](($s.version -split '\.')[0])
    if ($major -ge 13) { Add-Chequeo 'C01' 'Version de SQL Server >= 2016 (13.x)' 'Compatible' "Version $($s.version) $($s.nivel) - $($s.edicion)" }
    else { Add-Chequeo 'C01' 'Version de SQL Server >= 2016 (13.x)' 'Bloqueante' "Version $($s.version): la migracion usa SESSION_CONTEXT (2016)." }
    if ($s.nivel_compatibilidad -ge 130) { Add-Chequeo 'C02' 'Nivel de compatibilidad >= 130' 'Compatible' "Nivel $($s.nivel_compatibilidad) (las pruebas locales se ejecutaron en 130)" }
    else { Add-Chequeo 'C02' 'Nivel de compatibilidad >= 130' 'Requiere ajuste' "Nivel $($s.nivel_compatibilidad): las pruebas locales corrieron en 130; repetirlas en ese nivel." }
    if ($s.estado -eq 'ONLINE' -and -not $s.solo_lectura -and $s.acceso -eq 'MULTI_USER') { Add-Chequeo 'C03' 'Base en linea, lectura/escritura, multiusuario' 'Compatible' "$($s.estado) / $($s.acceso)" }
    else { Add-Chequeo 'C03' 'Base en linea, lectura/escritura, multiusuario' 'Bloqueante' "$($s.estado) / solo_lectura=$($s.solo_lectura) / $($s.acceso)" }
    if ($s.colacion -eq 'Latin1_General_100_CI_AI_SC') { Add-Chequeo 'C04' 'Colacion de la base' 'Compatible' $s.colacion }
    else { Add-Chequeo 'C04' 'Colacion de la base' 'Requiere ajuste' "Colacion $($s.colacion) (las pruebas usaron Latin1_General_100_CI_AI_SC; la migracion usa DATABASE_DEFAULT y comparaciones BIN2, pero repetir las pruebas con esa colacion)." }
    Add-Chequeo 'C05' 'Modelo de recuperacion (respaldo previo)' 'Informativo' "$($s.modelo_recuperacion)"
} else { Add-Chequeo 'C01' 'Version / base' 'No verificable' 'La consulta de servidor fallo.' }

if (Ok 'columnas') {
    $faltan = @()
    foreach ($t in @('registros_calidad_faret', 'registro_calidad_faret_defectos')) {
        if (-not (@($resultados['columnas'] | Where-Object { $_.tabla -eq $t }).Count)) { $faltan += $t }
    }
    if ($faltan.Count) { Add-Chequeo 'C06' 'Tablas Faret requeridas' 'Bloqueante' ("No existen: " + ($faltan -join ', ')) }
    else {
        Add-Chequeo 'C06' 'Tablas Faret requeridas' 'Compatible' 'registros_calidad_faret y registro_calidad_faret_defectos existen'
        $esperadas = @(
            @('registro_calidad_faret_defectos', 'id', 'int', 4), @('registro_calidad_faret_defectos', 'registro_id', 'int', 4), @('registro_calidad_faret_defectos', 'defecto', 'nvarchar', 300),
            @('registros_calidad_faret', 'id', 'int', 4), @('registros_calidad_faret', 'area_control', 'nvarchar', 100), @('registros_calidad_faret', 'area_defecto', 'nvarchar', 100))
        $dif = @()
        foreach ($e in $esperadas) {
            $c = Col $e[0] $e[1]
            if (-not $c) { $dif += "$($e[0]).$($e[1]) NO EXISTE" }
            elseif ($c.tipo -ne $e[2] -or $c.max_length -ne $e[3]) { $dif += "$($e[0]).$($e[1]) es $($c.tipo)($($c.max_length) bytes), se esperaba $($e[2])($($e[3]) bytes)" }
        }
        if ($dif.Count) { Add-Chequeo 'C07' 'Tipos y longitudes de columnas clave' 'Bloqueante' ($dif -join '; ') }
        else { Add-Chequeo 'C07' 'Tipos y longitudes de columnas clave' 'Compatible' 'Coinciden con el DDL documentado' }
        $idCol = Col 'registro_calidad_faret_defectos' 'id'
        if ($idCol -and -not $idCol.is_identity) { Add-Chequeo 'C08' 'defectos.id es IDENTITY' 'Requiere ajuste' 'No es IDENTITY (el DDL documentado lo indica).' }
        $ausentes = @()
        foreach ($n in @('eliminado', 'client_uuid', 'operador_registro', 'observaciones')) { if (-not (Col 'registros_calidad_faret' $n)) { $ausentes += $n } }
        if ($ausentes.Count) { Add-Chequeo 'C09' 'Columnas del backend actual en registros_calidad_faret (007/009)' 'Requiere ajuste' ("Faltan: " + ($ausentes -join ', ') + ' (el backend vigente las usa; revisar migraciones previas).') }
        else { Add-Chequeo 'C09' 'Columnas del backend actual en registros_calidad_faret (007/009)' 'Compatible' 'eliminado, client_uuid, operador_registro y observaciones presentes' }
        $nuevas = @($resultados['columnas'] | Where-Object { $_.tabla -eq 'registro_calidad_faret_defectos' -and ($_.columna -eq 'id_evento' -or $_.columna -eq 'criticidad') })
        if ($nuevas.Count) { Add-Chequeo 'C10' 'defectos ya tiene id_evento/criticidad' 'Requiere ajuste' 'La 010 (o parte) ya esta aplicada; la migracion es idempotente pero revisar el estado.' }
        else { Add-Chequeo 'C10' 'defectos sin id_evento/criticidad todavia' 'Compatible' 'Estado previo a la 010' }
    }
} else { Add-Chequeo 'C06' 'Esquema de columnas' 'No verificable' 'La consulta de columnas fallo.' }

if (Ok 'colisiones_010') {
    $n = @($resultados['colisiones_010']).Count
    if ($n -eq 0) { Add-Chequeo 'C11' 'Colisiones de nombres con objetos de la 010' 'Compatible' 'Ningun objeto de la 010 existe todavia' }
    else { Add-Chequeo 'C11' 'Colisiones de nombres con objetos de la 010' 'Requiere ajuste' ("$n objeto(s) con nombres de la 010 ya existen: " + ((@($resultados['colisiones_010'] | Select-Object -First 8 | ForEach-Object { $_.nombre })) -join ', ')) }
}

if (Ok 'triggers') {
    $tr = @($resultados['triggers'])
    if ($tr.Count -eq 0) { Add-Chequeo 'C12' 'Triggers existentes (tablas Faret y nivel base de datos)' 'Compatible' 'Ninguno' }
    else { Add-Chequeo 'C12' 'Triggers existentes (tablas Faret y nivel base de datos)' 'Requiere ajuste' ("Revisar interaccion con los triggers de la 010: " + (($tr | ForEach-Object { "$($_.trigger_nombre)@$($_.tabla)" }) -join ', ')) }
}

if (Ok 'dependencias') {
    $dep = @($resultados['dependencias'])
    $bloqSchema = @($dep | Where-Object { $_.schemabound -eq $true -and $_.tipo -in @('VIEW', 'SQL_STORED_PROCEDURE', 'SQL_SCALAR_FUNCTION', 'SQL_INLINE_TABLE_VALUED_FUNCTION', 'SQL_TABLE_VALUED_FUNCTION') })   # los CHECK propios de la tabla no cuentan
    if ($bloqSchema.Count) { Add-Chequeo 'C13' 'Objetos SCHEMABINDING sobre las tablas Faret' 'Bloqueante' ("Impiden ALTER TABLE: " + (($bloqSchema | ForEach-Object { $_.objeto }) -join ', ')) }
    elseif ($dep.Count) { Add-Chequeo 'C13' 'Vistas/procedimientos que referencian las tablas Faret' 'Informativo' ("$($dep.Count) referencia(s): " + (($dep | ForEach-Object { $_.objeto } | Select-Object -Unique) -join ', ')) }
    else { Add-Chequeo 'C13' 'Vistas/procedimientos que referencian las tablas Faret' 'Compatible' 'Ninguno' }
}
if (Ok 'modulos') {
    $m = @($resultados['modulos'])
    $riesgo = @($m | Where-Object { $_.usa_select_estrella -eq 1 -or $_.inserta_en_defectos -eq 1 -or $_.definicion_oculta -eq 1 })
    if ($riesgo.Count) { Add-Chequeo 'C14' 'Modulos con SELECT * / INSERT posicional / definicion oculta sobre las tablas Faret' 'Requiere ajuste' (($riesgo | ForEach-Object { $_.objeto }) -join ', ') }
    elseif ($m.Count) { Add-Chequeo 'C14' 'Modulos que mencionan las tablas Faret' 'Informativo' (($m | ForEach-Object { $_.objeto }) -join ', ') }
    else { Add-Chequeo 'C14' 'Modulos que mencionan las tablas Faret' 'Compatible' 'Ninguno (la unica consumidora es la API Node con INSERT de columnas nombradas)' }
}

if (Ok 'caracteristicas_tabla') {
    $malas = @($resultados['caracteristicas_tabla'] | Where-Object { $_.tabla -in @('registros_calidad_faret', 'registro_calidad_faret_defectos') -and ($_.is_memory_optimized -or $_.temporal_type -ne 0 -or $_.is_tracked_by_cdc -or $_.is_replicated -or $_.is_merge_published -or $_.change_tracking -eq 1) })
    if ($malas.Count) { Add-Chequeo 'C15' 'Tablas Faret con memoria optimizada / temporal / CDC / replicacion / change tracking' 'Requiere ajuste' (($malas | ForEach-Object { $_.tabla }) -join ', ') }
    else { Add-Chequeo 'C15' 'Tablas Faret con memoria optimizada / temporal / CDC / replicacion / change tracking' 'Compatible' 'Ninguna caracteristica especial' }
}

if (Ok 'usuario_app') {
    if ($resultados['usuario_app'][0].existe -eq 0) { Add-Chequeo 'C16' "Cuenta de la app ($UsuarioApp)" 'Requiere ajuste' 'No existe en la base: la migracion omite los GRANT (esta guardado) pero el backend usara otra cuenta; confirmar cual.' }
    else {
        $perm = @($resultados['permisos_app'])
        $sobre = @($perm | Where-Object { $_.objeto -eq 'registro_calidad_faret_defectos' })
        $tieneIns = @($sobre | Where-Object { $_.permiso -eq 'INSERT' -and $_.estado -like 'GRANT*' }).Count -gt 0
        $tieneSel = @($sobre | Where-Object { $_.permiso -eq 'SELECT' -and $_.estado -like 'GRANT*' }).Count -gt 0
        $roles = @($resultados['roles_app'] | ForEach-Object { $_.rol })
        $viaRol = ($roles -contains 'db_datawriter') -and ($roles -contains 'db_datareader')
        $peligro = @($perm | Where-Object { $_.permiso -in @('DELETE', 'ALTER', 'CONTROL') -and $_.estado -like 'GRANT*' })
        if (($tieneIns -and $tieneSel) -or $viaRol) { Add-Chequeo 'C16' "Permisos de la app sobre registro_calidad_faret_defectos" 'Compatible' "SELECT+INSERT presentes (roles: $($roles -join ', '))" }
        else { Add-Chequeo 'C16' "Permisos de la app sobre registro_calidad_faret_defectos" 'Requiere ajuste' 'No se ven SELECT e INSERT sobre la tabla de defectos: las columnas nuevas no quedarian cubiertas.' }
        if ($peligro.Count) { Add-Chequeo 'C17' 'Permisos amplios de la app (DELETE/ALTER/CONTROL)' 'Informativo' (($peligro | ForEach-Object { "$($_.permiso) en $($_.objeto)" }) -join ', ') }
    }
}
if (Ok 'permisos_ejecutor') {
    $e = $resultados['permisos_ejecutor'][0]
    if ($e.sysadmin -eq 1 -or $e.db_owner -eq 1 -or ($e.crear_tabla -eq 1 -and $e.crear_vista -eq 1 -and $e.alter_esquema_dbo -eq 1)) { Add-Chequeo 'C18' 'La cuenta que ejecuta este diagnostico tiene DDL' 'Compatible' "Podria ejecutar la 010 (sysadmin=$($e.sysadmin), db_owner=$($e.db_owner))" }
    else { Add-Chequeo 'C18' 'La cuenta que ejecuta este diagnostico tiene DDL' 'Informativo' 'Esta cuenta no tiene DDL; la 010 debe ejecutarla otra cuenta con CREATE TABLE/VIEW/TRIGGER y ALTER sobre dbo.' }
}

if (Ok 'volumen_defectos') {
    $f = [int64]$resultados['volumen_defectos'][0].filas
    if ($f -le 5000000) { Add-Chequeo 'C19' 'Volumen de defectos (ALTER y FK son de metadatos)' 'Compatible' "$f filas, texto maximo $($resultados['volumen_defectos'][0].largo_maximo) caracteres" }
    else { Add-Chequeo 'C19' 'Volumen de defectos (ALTER y FK son de metadatos)' 'Requiere ajuste' "$f filas: programar ventana." }
    if ($resultados['volumen_defectos'][0].largo_maximo -gt 150) { Add-Chequeo 'C20' 'Largo de defectos existentes' 'Requiere ajuste' 'Hay textos > 150 caracteres.' }
}
if (Ok 'volumen_registros') {
    $v = $resultados['volumen_registros'][0]
    Add-Chequeo 'C21' 'Registros historicos FARET' 'Informativo' "$($v.filas) inspecciones ($($v.desde) a $($v.hasta)); $($v.con_defectos) con defectos; $($v.con_defectos_sin_area_defecto) con defectos y SIN area_defecto"
}
if (Ok 'areas_defecto') {
    $validas = @('02-LAMINADO', '03-OFFSET', ('04-SERIGRAF' + [char]0x00CD + 'A'), '05-FOLIA', '07-TROQUELADO', '10-PEGADO', '12-FOLLETOS', '13-CORTE Y DIMENSIONADO')
    $fuera = @($resultados['areas_defecto'] | Where-Object { $_.area_defecto -and ($validas -notcontains $_.area_defecto) })
    if ($fuera.Count) { Add-Chequeo 'C22' 'area_defecto historicos fuera de las 8 etiquetas del catalogo' 'Informativo' (($fuera | ForEach-Object { "$($_.area_defecto) ($($_.filas))" }) -join ', ') }
    else { Add-Chequeo 'C22' 'area_defecto historicos fuera de las 8 etiquetas del catalogo' 'Compatible' 'Todas las etiquetas coinciden con el catalogo (el historico no se modifica de todos modos)' }
}
if (Ok 'respaldos') {
    $b = @($resultados['respaldos'])
    $full = @($b | Where-Object { $_.tipo -eq 'D' } | Select-Object -First 1)
    if (-not $full.Count) { Add-Chequeo 'C23' 'Respaldo COMPLETO registrado en msdb' 'Requiere ajuste' 'No hay respaldo completo registrado: hacerlo antes de ejecutar la 010.' }
    else { Add-Chequeo 'C23' 'Respaldo COMPLETO registrado en msdb' 'Informativo' "Ultimo completo: $($full[0].fin) ($($full[0].mb) MB). Hacer uno nuevo justo antes de la 010." }
} else { Add-Chequeo 'C23' 'Respaldo COMPLETO registrado en msdb' 'No verificable' 'Sin permiso sobre msdb o no disponible.' }
if ($fallos.Count) { Add-Chequeo 'C99' 'Consultas que no pudieron ejecutarse' 'No verificable' (($fallos | ForEach-Object { "$($_.consulta): $($_.error)" }) -join ' | ') }

$bloq = @($matriz | Where-Object { $_.estado -eq 'Bloqueante' }).Count
$ajus = @($matriz | Where-Object { $_.estado -eq 'Requiere ajuste' }).Count
$nover = @($matriz | Where-Object { $_.estado -eq 'No verificable' }).Count
if ($bloq -gt 0) { $veredicto = 'NO APTA: hay hallazgos BLOQUEANTES' }
elseif ($ajus -gt 0 -or $nover -gt 0) { $veredicto = 'PENDIENTE: revisar hallazgos "Requiere ajuste"/"No verificable" antes de decidir' }
else { $veredicto = 'SIN BLOQUEANTES ni ajustes (compatible segun metadatos)' }

# ------------------------------------------------------------------------------------------------
# Informe (.txt y .json) - metadatos y conteos solamente
# ------------------------------------------------------------------------------------------------
$marca = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not (Test-Path $Salida)) { New-Item -ItemType Directory -Path $Salida | Out-Null }
$txt = Join-Path $Salida "preflight_$marca.txt"
$json = Join-Path $Salida "preflight_$marca.json"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("DIAGNOSTICO SOLO LECTURA - migracion 010 (catalogo de eventos de calidad FARET)")
[void]$sb.AppendLine("Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Servidor: $Servidor  Base: $Base  Autenticacion: $Autenticacion")
[void]$sb.AppendLine("No se ejecuto ninguna sentencia de escritura. Contiene solo metadatos y conteos.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("VEREDICTO: $veredicto  (bloqueantes=$bloq, requieren ajuste=$ajus, no verificables=$nover)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("=== MATRIZ DE COMPATIBILIDAD ===")
[void]$sb.AppendLine(($matriz | Format-Table id, estado, tema, detalle -AutoSize -Wrap | Out-String -Width 250))
foreach ($k in $resultados.Keys) {
    [void]$sb.AppendLine("=== $k ===")
    if ($null -eq $resultados[$k]) { [void]$sb.AppendLine('(no disponible)') }
    elseif (@($resultados[$k]).Count -eq 0) { [void]$sb.AppendLine('(sin filas)') }
    else { [void]$sb.AppendLine((@($resultados[$k]) | Format-Table -AutoSize -Wrap | Out-String -Width 250)) }
}
[System.IO.File]::WriteAllText($txt, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
$salidaJson = [ordered]@{ fecha = (Get-Date).ToString('s'); servidor = $Servidor; base = $Base; veredicto = $veredicto; matriz = $matriz; datos = $resultados }
[System.IO.File]::WriteAllText($json, ($salidaJson | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ''
Write-Host "VEREDICTO: $veredicto"
$matriz | Format-Table id, estado, tema -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "Informe: $txt"
Write-Host "JSON:    $json"

# ------------------------------------------------------------------------------------------------
# Evidencia para los pasos siguientes (02/04 la exigen): solo si NO hay bloqueantes ni 010 ya aplicada
# ------------------------------------------------------------------------------------------------
$cmdN = $conexion.CreateCommand(); $cmdN.CommandText = "SELECT @@SERVERNAME"; $nombreReal = [string]$cmdN.ExecuteScalar()
$cmdA = $conexion.CreateCommand(); $cmdA.CommandText = "SELECT CASE WHEN OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL THEN 0 ELSE 1 END"; $yaAplicada = [int]$cmdA.ExecuteScalar()
$cmdP = $conexion.CreateCommand(); $cmdP.CommandText = "SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)"; $mayor = [int]$cmdP.ExecuteScalar()
$ajusSinRespaldo = @($matriz | Where-Object { $_.estado -eq "Requiere ajuste" -and $_.id -ne "C23" }).Count   # C23 (respaldo previo) lo resuelve 02_Respaldo
$okEvid = ($bloq -eq 0 -and $ajusSinRespaldo -eq 0 -and $yaAplicada -eq 0 -and $mayor -ge 13)
$evid = [ordered]@{ fecha = (Get-Date).ToString('s'); servidor = $nombreReal; base = $Base; apto = $okEvid; bloqueantes = $bloq; requieren_ajuste = $ajus;
                    no_verificables = $nover; migracion_010_ya_aplicada = [bool]$yaAplicada; version_mayor = $mayor; informe = $json }
if ($okEvid) { $evid['veredicto'] = 'APTO para continuar con 02_Respaldo' } else { $evid['veredicto'] = 'NO continuar: revisar la matriz del informe' }
$archEvid = Join-Path $Salida ("preflight_ok_{0}.json" -f $marca)
if ($okEvid) { [System.IO.File]::WriteAllText($archEvid, ($evid | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($true))); Write-Host "Evidencia: $archEvid" -ForegroundColor Green }
else { Write-Host ("NO se genero evidencia de preflight OK (ajustes={0}, bloqueantes={1}, 010 ya aplicada={2}, version mayor={3})." -f $ajus, $bloq, $yaAplicada, $mayor) -ForegroundColor Yellow }
$conexion.Close()
if (-not $okEvid) { exit 2 }
