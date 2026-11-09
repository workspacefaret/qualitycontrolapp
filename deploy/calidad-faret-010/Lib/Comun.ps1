<#
  Funciones comunes del paquete calidad-faret-010. Se carga con:  . (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
  - Solo ASCII (compatible con Windows PowerShell 5.1 sin importar la codificacion del archivo).
  - NUNCA guarda ni escribe contrasenas: con autenticacion SQL la clave se pide como SecureString y vive solo en memoria.
  - Toda escritura (BACKUP, migracion, rollback) exige una frase de confirmacion exacta que incluye el servidor y la base REALES
    informados por el propio servidor (@@SERVERNAME), para evitar ejecutar contra el destino equivocado.
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

$script:RaizPaquete = Split-Path -Parent $PSScriptRoot
$script:DirSalida = Join-Path $script:RaizPaquete 'salida'
$script:DirLogs = Join-Path $script:RaizPaquete 'logs'
$script:ArchivoLog = $null

function Initialize-Paquete([string]$nombreScript) {
    foreach ($d in @($script:DirSalida, $script:DirLogs)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    $script:ArchivoLog = Join-Path $script:DirLogs ("{0}_{1}.log" -f $nombreScript, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-Log "Inicio de $nombreScript (usuario Windows: $env:USERDOMAIN\$env:USERNAME, equipo: $env:COMPUTERNAME)"
}

function Write-Log([string]$mensaje, [string]$nivel = 'INFO') {
    $linea = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $nivel, $mensaje
    $color = switch ($nivel) { 'ERROR' { 'Red' } 'WARN' { 'Yellow' } 'OK' { 'Green' } default { 'Gray' } }
    Write-Host $linea -ForegroundColor $color
    if ($script:ArchivoLog) { Add-Content -Path $script:ArchivoLog -Value $linea -Encoding UTF8 }
}

# ------------------------------------------------------------------------------------------------
# Integridad del paquete
# ------------------------------------------------------------------------------------------------
function Test-Manifiesto([switch]$Silencioso) {
    $manifiesto = Join-Path $script:RaizPaquete 'MANIFEST.sha256'
    if (-not (Test-Path $manifiesto)) { throw "No existe MANIFEST.sha256 en $($script:RaizPaquete)." }
    $malos = @(); $n = 0
    foreach ($linea in (Get-Content $manifiesto -Encoding UTF8)) {
        if ($linea -match '^\s*#' -or -not $linea.Trim()) { continue }
        if ($linea -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Linea invalida en MANIFEST.sha256: $linea" }
        $hash = $Matches[1].ToLower(); $rel = $Matches[2].Trim()
        $ruta = Join-Path $script:RaizPaquete $rel
        $n++
        if (-not (Test-Path $ruta)) { $malos += "FALTA: $rel"; continue }
        $real = (Get-FileHash -Algorithm SHA256 -Path $ruta).Hash.ToLower()
        if ($real -ne $hash) { $malos += "DISTINTO: $rel" }
    }
    if ($malos.Count) {
        foreach ($m in $malos) { Write-Log $m 'ERROR' }
        throw "El paquete NO coincide con MANIFEST.sha256 ($($malos.Count) archivo(s)). No continue: vuelva a copiar el paquete completo."
    }
    if (-not $Silencioso) { Write-Log "Manifiesto SHA-256 verificado: $n archivos identicos a los preparados." 'OK' }
}

# ------------------------------------------------------------------------------------------------
# Conexion
# ------------------------------------------------------------------------------------------------
function Open-Conexion([string]$Servidor, [string]$Base, [string]$Autenticacion, [string]$Usuario, [bool]$ConfiarCertificado, [string]$Aplicacion) {
    $csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $csb['Data Source'] = $Servidor
    $csb['Initial Catalog'] = $Base
    $csb['Application Name'] = $Aplicacion
    $csb['Connect Timeout'] = 15
    if ($ConfiarCertificado) { $csb['TrustServerCertificate'] = $true }
    if ($Autenticacion -eq 'Windows') {
        $csb['Integrated Security'] = $true
        $con = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString)
    } else {
        if (-not $Usuario) { throw 'Con -Autenticacion Sql debe indicar -Usuario.' }
        $clave = Read-Host -AsSecureString -Prompt "Clave de $Usuario (no se muestra ni se guarda)"
        $clave.MakeReadOnly()
        $cred = New-Object System.Data.SqlClient.SqlCredential($Usuario, $clave)
        $con = New-Object System.Data.SqlClient.SqlConnection($csb.ConnectionString, $cred)
    }
    $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] { param($s, $e) Write-Host ("   SQL: " + $e.Message) -ForegroundColor DarkGray }
    $con.add_InfoMessage($handler)
    $con.FireInfoMessageEventOnUserErrors = $false
    $con.Open()
    return $con
}

function Invoke-Filas($con, [string]$sql, [hashtable]$parametros = @{}, [int]$timeout = 60) {
    $cmd = $con.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $timeout
    foreach ($k in $parametros.Keys) { [void]$cmd.Parameters.AddWithValue($k, $parametros[$k]) }
    $dt = New-Object System.Data.DataTable
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    [void]$da.Fill($dt)
    $filas = @()
    foreach ($r in $dt.Rows) {
        $o = [ordered]@{}
        foreach ($c in $dt.Columns) { $v = $r[$c.ColumnName]; if ($v -is [System.DBNull]) { $v = $null }; $o[$c.ColumnName] = $v }
        $filas += [pscustomobject]$o
    }
    return , $filas
}

function Invoke-Escalar($con, [string]$sql, [hashtable]$parametros = @{}, [int]$timeout = 60) {
    $f = Invoke-Filas $con $sql $parametros $timeout
    if ($f.Count -eq 0) { return $null }
    return ($f[0].PSObject.Properties | Select-Object -First 1).Value
}

function Invoke-SinResultado($con, [string]$sql, [hashtable]$parametros = @{}, [int]$timeout = 60) {
    $cmd = $con.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $timeout
    foreach ($k in $parametros.Keys) { [void]$cmd.Parameters.AddWithValue($k, $parametros[$k]) }
    [void]$cmd.ExecuteNonQuery()
}

function Get-InfoDestino($con) {
    $f = Invoke-Filas $con @"
SELECT @@SERVERNAME AS servidor, DB_NAME() AS base, CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(40)) AS version,
       CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100)) AS edicion, d.compatibility_level AS compat, d.state_desc AS estado,
       d.recovery_model_desc AS recuperacion, SUSER_SNAME() AS cuenta
FROM sys.databases d WHERE d.name = DB_NAME()
"@
    return $f[0]
}

function Show-Destino($info) {
    Write-Host ''
    Write-Host '  DESTINO' -ForegroundColor Cyan
    Write-Host ("    Servidor : {0}" -f $info.servidor)
    Write-Host ("    Base     : {0}  ({1}, compatibilidad {2}, recuperacion {3})" -f $info.base, $info.estado, $info.compat, $info.recuperacion)
    Write-Host ("    SQL      : {0}  {1}" -f $info.version, $info.edicion)
    Write-Host ("    Cuenta   : {0}" -f $info.cuenta)
    Write-Host ''
}

# ------------------------------------------------------------------------------------------------
# Confirmacion explicita antes de toda escritura
# ------------------------------------------------------------------------------------------------
function Confirm-Escritura([string]$accion, [string]$frase, [string]$confirmar) {
    Write-Host ''
    Write-Host "  ACCION QUE ESCRIBE: $accion" -ForegroundColor Yellow
    Write-Host "  Para continuar escriba EXACTAMENTE la frase siguiente (cualquier otra cosa cancela sin hacer nada):" -ForegroundColor Yellow
    Write-Host "      $frase" -ForegroundColor White
    $respuesta = $confirmar
    if (-not $respuesta) { $respuesta = Read-Host -Prompt '  Frase' }
    if ($respuesta -cne $frase) { throw 'Confirmacion incorrecta: no se hizo ningun cambio.' }
    Write-Log "Confirmacion recibida para: $accion"
}

# ------------------------------------------------------------------------------------------------
# Evidencias entre pasos (JSON en salida\)
# ------------------------------------------------------------------------------------------------
function Save-Evidencia([string]$nombre, $objeto) {
    $ruta = Join-Path $script:DirSalida $nombre
    [System.IO.File]::WriteAllText($ruta, ($objeto | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($true)))
    Write-Log "Evidencia guardada: $ruta"
    return $ruta
}

function Get-UltimaEvidencia([string]$patron, [int]$maxHoras, [string]$servidorEsperado, [string]$baseEsperada) {
    $a = @(Get-ChildItem -Path $script:DirSalida -Filter $patron -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($f in $a) {
        $j = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.base -ne $baseEsperada) { continue }
        if ($servidorEsperado -and $j.servidor -ne $servidorEsperado) { continue }
        if (((Get-Date) - $f.LastWriteTime).TotalHours -gt $maxHoras) { continue }
        return [pscustomobject]@{ archivo = $f.FullName; datos = $j }
    }
    return $null
}

# ------------------------------------------------------------------------------------------------
# Ejecucion de un archivo SQL (un solo lote, sin GO), leido como UTF-8
# ------------------------------------------------------------------------------------------------
function Read-ArchivoSql([string]$ruta, [bool]$ExigirTildes = $true) {
    if (-not (Test-Path $ruta)) { throw "No existe el archivo SQL: $ruta" }
    $texto = [System.IO.File]::ReadAllText($ruta, (New-Object System.Text.UTF8Encoding($false)))
    if ($texto -match '(?im)^\s*GO\s*$') { throw "$ruta contiene GO: el paquete ejecuta un solo lote." }
    if ($ExigirTildes -and -not $texto.Contains([string][char]0x00CD)) { throw "$ruta no parece UTF-8 valido (faltan tildes esperadas)." }
    return $texto
}

function Invoke-LoteSql($con, [string]$texto, [int]$timeout = 300) {
    $cmd = $con.CreateCommand(); $cmd.CommandText = $texto; $cmd.CommandTimeout = $timeout
    $resultado = @()
    try {
        $rd = $cmd.ExecuteReader()
        do {
            $dt = New-Object System.Data.DataTable
            $dt.Load($rd)
            foreach ($r in $dt.Rows) {
                $o = [ordered]@{}
                foreach ($c in $dt.Columns) { $v = $r[$c.ColumnName]; if ($v -is [System.DBNull]) { $v = $null }; $o[$c.ColumnName] = $v }
                $resultado += [pscustomobject]$o
            }
        } while (-not $rd.IsClosed -and $rd.NextResult())
        if (-not $rd.IsClosed) { $rd.Close() }
    } catch [System.Data.SqlClient.SqlException] {
        $e = $_.Exception
        $detalle = "SQL error $($e.Number), linea $($e.LineNumber): $($e.Message)"
        if ($e.Number -eq 1222) { $detalle += ' (bloqueo no obtenido en 5 s: hay una operacion en curso sobre la tabla; no se cambio nada, reintente en unos minutos)' }
        throw $detalle
    }
    return , $resultado
}

function Test-NombreBase([string]$base) {
    if ($base -notmatch '^[A-Za-z0-9_]{1,128}$') { throw "Nombre de base no permitido: $base" }
}
