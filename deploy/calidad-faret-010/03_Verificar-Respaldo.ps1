<#
 Verifica el respaldo hecho por 02_Respaldo con RESTORE VERIFYONLY ... WITH CHECKSUM y RESTORE HEADERONLY.
 NO restaura nada: VERIFYONLY solo lee el archivo y comprueba que es utilizable. No escribe en ninguna base.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [string]$Archivo,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [switch]$ConfiarCertificado,
    [int]$MaxHoras = 24
)
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '03_Verificar-Respaldo'
Test-NombreBase $Base
Test-Manifiesto -Silencioso
$con = Open-Conexion $Servidor $Base $Autenticacion $Usuario ([bool]$ConfiarCertificado) 'calidad010_03_verificar'
try {
    $info = Get-InfoDestino $con
    Show-Destino $info
    if (-not $Archivo) {
        $ev = Get-UltimaEvidencia 'respaldo_2*.json' $MaxHoras $info.servidor $Base
        if (-not $ev) { throw 'No hay evidencia de 02_Respaldo reciente; indique -Archivo con la ruta del .bak (en el servidor).' }
        $Archivo = $ev.datos.archivo
    }
    Write-Log "Verificando: $Archivo"
    $h = Invoke-Filas $con 'RESTORE HEADERONLY FROM DISK = @a' @{ '@a' = $Archivo } 300
    if ($h.Count -ne 1) { throw "El archivo contiene $($h.Count) respaldos; se esperaba 1." }
    $x = $h[0]
    if ($x.DatabaseName -ne $Base) { throw "El respaldo es de la base '$($x.DatabaseName)', no de '$Base'." }
    if ([int]$x.BackupType -ne 1) { throw 'El respaldo no es un respaldo completo de base de datos.' }
    if ($x.HasBackupChecksums -ne $true) { throw 'El respaldo no tiene checksums (HasBackupChecksums = 0).' }
    if ($x.IsCopyOnly -ne $true) { Write-Log 'El respaldo no es COPY_ONLY.' 'WARN' }
    Write-Log "Cabecera: base=$($x.DatabaseName) fin=$($x.BackupFinishDate) compat=$($x.CompatibilityLevel) tamano_MB=$([math]::Round($x.BackupSize/1MB,1))" 'OK'
    $cmd = $con.CreateCommand(); $cmd.CommandText = 'RESTORE VERIFYONLY FROM DISK = @a WITH CHECKSUM'; $cmd.CommandTimeout = 0
    [void]$cmd.Parameters.AddWithValue('@a', $Archivo); [void]$cmd.ExecuteNonQuery()
    Write-Log 'RESTORE VERIFYONLY: el respaldo es valido (checksums correctos).' 'OK'
    Save-Evidencia ("respaldo_verificado_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss')) ([ordered]@{
        fecha = (Get-Date).ToString('s'); servidor = $info.servidor; base = $Base; archivo = $Archivo; backup_finish = $x.BackupFinishDate.ToString('s')
        tamano_mb = [math]::Round($x.BackupSize / 1MB, 1); copy_only = [bool]$x.IsCopyOnly; verifyonly = 'OK' }) | Out-Null
} finally { $con.Close() }
