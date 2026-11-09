<#
 Verifica que TODOS los archivos del paquete son identicos a los preparados (SHA-256 contra MANIFEST.sha256).
 No se conecta a ningun servidor. Ejecutar siempre tras copiar el paquete a otro equipo.
#>
[CmdletBinding()] param()
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '00_Verificar-Manifiesto'
Test-Manifiesto
