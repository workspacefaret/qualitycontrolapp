<#
 Respaldo COMPLETO (COPY_ONLY, CHECKSUM, COMPRESSION) de calidad_db, escrito en una carpeta DEL SERVIDOR SQL.
 - COPY_ONLY: no altera la cadena de respaldos diferenciales/log del DBA.
 - Nombre unico con fecha y hora: nunca sobrescribe un respaldo anterior (INIT solo aplica a ese archivo nuevo).
 - Exige evidencia de preflight OK reciente y una frase de confirmacion que incluye el servidor y la base reales.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [Parameter(Mandatory = $true)][string]$RutaRespaldo,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [switch]$ConfiarCertificado,
    [string]$Confirmar,
    [switch]$SinCompresion,   # solo para ediciones sin compresion (Express); SQL Server Standard 2016 la soporta
    [int]$MaxHorasPreflight = 24
)
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '02_Respaldo'
Test-NombreBase $Base
Test-Manifiesto -Silencioso
if ($RutaRespaldo -notmatch '^([A-Za-z]:\\|\\\\)[^"''<>|*?;]+$') { throw 'RutaRespaldo debe ser una ruta absoluta del servidor SQL (C:\... o \\servidor\...) sin caracteres especiales.' }

$con = Open-Conexion $Servidor $Base $Autenticacion $Usuario ([bool]$ConfiarCertificado) 'calidad010_02_respaldo'
try {
    $info = Get-InfoDestino $con
    Show-Destino $info
    $pf = Get-UltimaEvidencia 'preflight_ok_*.json' $MaxHorasPreflight $info.servidor $Base
    if (-not $pf) { throw "No hay evidencia de 01_Preflight OK de las ultimas $MaxHorasPreflight h para $($info.servidor)/$Base. Ejecute 01_Preflight.ps1 primero." }
    Write-Log "Preflight OK encontrado: $($pf.archivo)" 'OK'

    $marca = Get-Date -Format 'yyyyMMdd_HHmmss'
    $archivo = (Join-Path $RutaRespaldo ("{0}_pre010_{1}.bak" -f $Base, $marca))
    $frase = "RESPALDAR $($info.base) EN $($info.servidor)"
    Confirm-Escritura "BACKUP DATABASE [$($info.base)] TO DISK = '$archivo' (COPY_ONLY, CHECKSUM, COMPRESSION). No modifica datos; usa disco e IO del servidor." $frase $Confirmar

    $comp = "COMPRESSION, "; if ($SinCompresion) { $comp = "" }
    $sql = "BACKUP DATABASE [$Base] TO DISK = @ruta WITH COPY_ONLY, CHECKSUM, ${comp}INIT, STATS = 10, NAME = @nombre"
    $inicio = Get-Date
    $cmd = $con.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 0
    [void]$cmd.Parameters.AddWithValue('@ruta', $archivo)
    [void]$cmd.Parameters.AddWithValue('@nombre', "$Base pre-010 $marca")
    [void]$cmd.ExecuteNonQuery()
    $seg = [int]((Get-Date) - $inicio).TotalSeconds
    Write-Log "Respaldo terminado en $seg s: $archivo" 'OK'

    Save-Evidencia ("respaldo_{0}.json" -f $marca) ([ordered]@{
        fecha = (Get-Date).ToString('s'); servidor = $info.servidor; base = $Base; archivo = $archivo; segundos = $seg; verificado = $false
        siguiente_paso = '03_Verificar-Respaldo.ps1' }) | Out-Null
    Write-Log 'SIGUIENTE: 03_Verificar-Respaldo.ps1 (RESTORE VERIFYONLY). No aplique la migracion sin ese paso.' 'WARN'
} finally { $con.Close() }
