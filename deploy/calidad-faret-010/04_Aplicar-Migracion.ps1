<#
 Aplica la migracion 010 (sql\010_catalogo_eventos_calidad_faret.sql) en UN solo lote transaccional.
 Requisitos (los exige el script): manifiesto OK, preflight OK reciente, respaldo verificado reciente, frase de confirmacion.
 Antes de aplicar guarda una foto del estado (conteos, checksums, max id, client_uuid) para 05_Verificacion-Posterior.
 Si falla, la transaccion se revierte sola (XACT_ABORT): la base queda como estaba. Error 1222 = bloqueo: reintente.
 La cuenta que lo ejecuta necesita DDL (CREATE TABLE/VIEW/TRIGGER, ALTER en las 2 tablas Faret y GRANT). NO ampliar permisos de la app.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [switch]$ConfiarCertificado,
    [string]$Confirmar,
    [int]$MaxHorasPreflight = 24,
    [int]$MaxHorasRespaldo = 12
)
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '04_Aplicar-Migracion'
Test-NombreBase $Base
Test-Manifiesto -Silencioso
$sqlTexto = Read-ArchivoSql (Join-Path $script:RaizPaquete 'sql\010_catalogo_eventos_calidad_faret.sql')

$con = Open-Conexion $Servidor $Base $Autenticacion $Usuario ([bool]$ConfiarCertificado) 'calidad010_04_aplicar'
try {
    $info = Get-InfoDestino $con
    Show-Destino $info
    $pf = Get-UltimaEvidencia 'preflight_ok_*.json' $MaxHorasPreflight $info.servidor $Base
    if (-not $pf) { throw "Falta preflight OK de las ultimas $MaxHorasPreflight h. Ejecute 01_Preflight.ps1." }
    $rv = Get-UltimaEvidencia 'respaldo_verificado_*.json' $MaxHorasRespaldo $info.servidor $Base
    if (-not $rv) { throw "Falta respaldo VERIFICADO de las ultimas $MaxHorasRespaldo h. Ejecute 02_Respaldo.ps1 y 03_Verificar-Respaldo.ps1." }
    if ($rv.datos.verifyonly -ne 'OK') { throw 'El respaldo no figura como verificado.' }
    Write-Log "Preflight: $($pf.archivo)" 'OK'
    Write-Log "Respaldo verificado: $($rv.datos.archivo)" 'OK'

    if ([int](Invoke-Escalar $con "SELECT CASE WHEN OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL THEN 0 ELSE 1 END") -eq 1) {
        throw 'La migracion 010 ya esta aplicada en esta base. Nada que hacer (use 05_Verificacion-Posterior.ps1).'
    }

    # Foto previa
    $pre = (Invoke-Filas $con @"
SELECT (SELECT COUNT_BIG(*) FROM dbo.registros_calidad_faret) AS registros,
       (SELECT ISNULL(MAX(id),0) FROM dbo.registros_calidad_faret) AS registros_max_id,
       (SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM dbo.registros_calidad_faret) AS registros_checksum,
       (SELECT COUNT_BIG(*) FROM dbo.registro_calidad_faret_defectos) AS defectos,
       (SELECT ISNULL(MAX(id),0) FROM dbo.registro_calidad_faret_defectos) AS defectos_max_id,
       (SELECT CHECKSUM_AGG(CHECKSUM(id, registro_id, defecto)) FROM dbo.registro_calidad_faret_defectos) AS defectos_checksum,
       (SELECT COUNT(client_uuid) FROM dbo.registros_calidad_faret) AS client_uuid_con_valor,
       (SELECT COUNT(DISTINCT client_uuid) FROM dbo.registros_calidad_faret) AS client_uuid_distintos,
       (SELECT COUNT_BIG(*) FROM sys.tables) AS tablas_totales
"@)[0]
    Write-Log ("Estado previo: {0} inspecciones, {1} defectos, {2} client_uuid ({3} distintos)" -f $pre.registros, $pre.defectos, $pre.client_uuid_con_valor, $pre.client_uuid_distintos)
    $marca = Get-Date -Format 'yyyyMMdd_HHmmss'
    $archPre = Save-Evidencia ("estado_previo_{0}.json" -f $marca) ([ordered]@{ fecha = (Get-Date).ToString('s'); servidor = $info.servidor; base = $Base; estado = $pre })

    $frase = "APLICAR 010 EN $($info.servidor) $($info.base)"
    Confirm-Escritura "Ejecutar sql\010_catalogo_eventos_calidad_faret.sql (crea 3 tablas, 1 vista, 6 triggers, 2 columnas nulas + FK/CHECK/indice en registro_calidad_faret_defectos, 3 GRANT SELECT). No modifica filas existentes." $frase $Confirmar

    $t0 = Get-Date
    $res = Invoke-LoteSql $con $sqlTexto 600
    Write-Log ("Migracion aplicada en {0:N1} s." -f ((Get-Date) - $t0).TotalSeconds) 'OK'
    if ($res.Count) { Write-Host ($res | Format-Table -AutoSize | Out-String) }
    Save-Evidencia ("migracion_aplicada_{0}.json" -f $marca) ([ordered]@{ fecha = (Get-Date).ToString('s'); servidor = $info.servidor; base = $Base; cuenta = $info.cuenta
        resumen = $res; estado_previo = $archPre; respaldo = $rv.datos.archivo }) | Out-Null
    Write-Log 'SIGUIENTE: 05_Verificacion-Posterior.ps1. NO despliegue el backend hasta que termine sin FALLOS.' 'WARN'
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log 'Si el error ocurrio dentro del SQL, la transaccion se revirtio. Compruebe con 01_Preflight.ps1 / RECUPERACION.md.' 'ERROR'
    throw
} finally { $con.Close() }
