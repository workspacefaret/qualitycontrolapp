<#
 Revierte la migracion 010 (sql\010_catalogo_eventos_calidad_faret_rollback.sql). NUNCA restaura una base: solo quita lo que agrego la 010,
 respaldando antes catalogo, auditoria y defectos con id_evento en tablas bak010_<fecha>_* (que no se borran).
 Si ya hay defectos registrados con id_evento el SQL se niega, salvo -PermitirConDatos (los respalda primero).
 Exige un respaldo verificado reciente, salvo -SinRespaldo (solo si el DBA lo decide expresamente).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [switch]$ConfiarCertificado,
    [switch]$PermitirConDatos,
    [switch]$SinRespaldo,
    [string]$Confirmar,
    [int]$MaxHorasRespaldo = 72
)
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '06_Rollback'
Test-NombreBase $Base
Test-Manifiesto -Silencioso
$sqlTexto = Read-ArchivoSql (Join-Path $script:RaizPaquete 'sql\010_catalogo_eventos_calidad_faret_rollback.sql') $false
$linea = 'DECLARE @permitir_con_datos BIT = 0;'
if (-not $sqlTexto.Contains($linea)) { throw 'El SQL de rollback no tiene la linea esperada de @permitir_con_datos.' }
if ($PermitirConDatos) { $sqlTexto = $sqlTexto.Replace($linea, 'DECLARE @permitir_con_datos BIT = 1;') }

$con = Open-Conexion $Servidor $Base $Autenticacion $Usuario ([bool]$ConfiarCertificado) 'calidad010_06_rollback'
try {
    $info = Get-InfoDestino $con
    Show-Destino $info
    if (-not $SinRespaldo) {
        $rv = Get-UltimaEvidencia 'respaldo_verificado_*.json' $MaxHorasRespaldo $info.servidor $Base
        if (-not $rv) { throw "No hay respaldo verificado de las ultimas $MaxHorasRespaldo h. Haga 02/03 o use -SinRespaldo bajo responsabilidad del DBA." }
    }
    $frase = "REVERTIR 010 EN $($info.servidor) $($info.base)"
    $extra = ''
    if ($PermitirConDatos) { $extra = ' CON -PermitirConDatos (respalda en bak010_* los defectos con id_evento y luego quita las columnas).' }
    Confirm-Escritura ("Ejecutar el rollback de la 010: quita tablas de catalogo, vista, triggers y 2 columnas." + $extra + " No borra inspecciones ni defectos.") $frase $Confirmar
    $res = Invoke-LoteSql $con $sqlTexto 600
    if ($res.Count) { Write-Host ($res | Format-Table -AutoSize | Out-String) }
    $quedan = Invoke-Escalar $con "SELECT CASE WHEN OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL AND COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NULL THEN 1 ELSE 0 END"
    if ([int]$quedan -ne 1) { throw 'Tras el rollback quedan objetos de la 010.' }
    Write-Log 'Rollback terminado y verificado: la base ya no contiene objetos de la 010. Respaldos internos: tablas bak010_* (no se borran).' 'OK'
} finally { $con.Close() }
