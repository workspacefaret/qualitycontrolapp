<#
 Verificacion posterior SOLO LECTURA de la migracion 010. Compara contra la foto previa (estado_previo_*.json).
 Termina con codigo 0 solo si no hay FALLOS.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [string]$Base = 'calidad_db',
    [ValidateSet('Windows', 'Sql')][string]$Autenticacion = 'Windows',
    [string]$Usuario,
    [switch]$ConfiarCertificado,
    [string]$UsuarioApp = 'quality_control_backend_sql',
    [int]$MaxHoras = 72
)
. (Join-Path $PSScriptRoot 'Lib\Comun.ps1')
Initialize-Paquete '05_Verificacion-Posterior'
Test-NombreBase $Base
$con = Open-Conexion $Servidor $Base $Autenticacion $Usuario ([bool]$ConfiarCertificado) 'calidad010_05_posterior'
$script:fallos = 0
$script:resultados = @()
function Check([string]$id, [string]$desc, [bool]$ok, [string]$detalle) {
    $script:resultados += [pscustomobject]@{ id = $id; descripcion = $desc; ok = $ok; detalle = $detalle }
    if ($ok) { Write-Log "PASS $id $desc ($detalle)" 'OK' } else { $script:fallos++; Write-Log "FALLO $id $desc ($detalle)" 'ERROR' }
}
try {
    Invoke-SinResultado $con 'SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED'
    $info = Get-InfoDestino $con
    Show-Destino $info
    $pre = Get-UltimaEvidencia 'estado_previo_*.json' $MaxHoras $info.servidor $Base
    $n = (Invoke-Filas $con @"
SELECT (SELECT COUNT(*) FROM dbo.calidad_faret_areas) AS areas,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos) AS eventos,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad = N'Critico') AS crit,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad = N'Mayor') AS mayor,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE criticidad = N'Menor') AS menor,
       (SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables) AS operables,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE aprobacion = N'PENDIENTE') AS pendientes,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos e WHERE e.requiere_aprobacion = 1 AND EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables v WHERE v.id_evento = e.id_evento)) AS pendientes_operables,
       (SELECT COUNT(*) FROM dbo.calidad_faret_catalogo_auditoria) AS auditoria,
       (SELECT COUNT(*) FROM dbo.registro_calidad_faret_defectos WHERE id_evento IS NOT NULL OR criticidad IS NOT NULL) AS defectos_con_catalogo,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE defecto <> defecto_origen OR criticidad <> criticidad_origen) AS eventos_desviados
"@)[0]
    Check 'P01' '8 areas' ($n.areas -eq 8) "areas=$($n.areas)"
    Check 'P02' '57 eventos' ($n.eventos -eq 57) "eventos=$($n.eventos)"
    Check 'P03' 'Criticidad 42/14/1' ($n.crit -eq 42 -and $n.mayor -eq 14 -and $n.menor -eq 1) "$($n.crit)/$($n.mayor)/$($n.menor)"
    Check 'P04' '52 eventos operables' ($n.operables -eq 52) "operables=$($n.operables)"
    Check 'P05' '5 pendientes de Calidad y ninguno operable' ($n.pendientes -eq 5 -and $n.pendientes_operables -eq 0) "pendientes=$($n.pendientes), operables entre ellos=$($n.pendientes_operables)"
    Check 'P06' 'Auditoria de carga inicial = 8 + 57' ($n.auditoria -eq 65) "auditoria=$($n.auditoria)"
    Check 'P07' 'Ningun defecto historico recibio id_evento/criticidad' ($n.defectos_con_catalogo -eq 0) "con catalogo=$($n.defectos_con_catalogo)"
    Check 'P08' 'Texto y criticidad vigentes = origen (Excel)' ($n.eventos_desviados -eq 0) "desviados=$($n.eventos_desviados)"

    $c = (Invoke-Filas $con @"
SELECT (SELECT COUNT(*) FROM sys.triggers WHERE name IN (N'TR_registro_calidad_faret_defectos_evento', N'TR_calidad_faret_eventos_upd', N'TR_calidad_faret_eventos_del', N'TR_calidad_faret_areas_upd', N'TR_calidad_faret_areas_del', N'TR_calidad_faret_catalogo_auditoria_inmutable') AND is_disabled = 0) AS triggers_activos,
       (SELECT COUNT(*) FROM sys.foreign_keys WHERE name = N'FK_registro_calidad_faret_defectos_evento' AND is_not_trusted = 0 AND is_disabled = 0) AS fk_ok,
       (SELECT COUNT(*) FROM sys.check_constraints WHERE name = N'CK_registro_calidad_faret_defectos_evento_crit' AND is_not_trusted = 0 AND is_disabled = 0) AS ck_ok,
       (SELECT COUNT(*) FROM sys.indexes WHERE name = N'IX_registro_calidad_faret_defectos_id_evento' AND has_filter = 1) AS ix_ok
"@)[0]
    Check 'P09' '6 triggers habilitados' ($c.triggers_activos -eq 6) "triggers=$($c.triggers_activos)"
    Check 'P10' 'FK, CHECK confiables e indice filtrado' ($c.fk_ok -eq 1 -and $c.ck_ok -eq 1 -and $c.ix_ok -eq 1) "fk=$($c.fk_ok) ck=$($c.ck_ok) ix=$($c.ix_ok)"

    $g = Invoke-Filas $con @"
SELECT o.name AS objeto, p.permission_name AS permiso, p.state_desc AS estado
FROM sys.database_permissions p JOIN sys.objects o ON o.object_id = p.major_id JOIN sys.database_principals u ON u.principal_id = p.grantee_principal_id
WHERE u.name = @u AND o.name IN (N'calidad_faret_areas', N'calidad_faret_eventos', N'vw_calidad_faret_eventos_operables', N'calidad_faret_catalogo_auditoria')
"@ @{ '@u' = $UsuarioApp }
    $solo = @($g | Where-Object { $_.permiso -eq 'SELECT' -and $_.estado -eq 'GRANT' }).Count
    $otros = @($g | Where-Object { $_.permiso -ne 'SELECT' }).Count
    $hayCuenta = [int](Invoke-Escalar $con 'SELECT COUNT(*) FROM sys.database_principals WHERE name = @u' @{ '@u' = $UsuarioApp })
    if ($hayCuenta -eq 0) { Check 'P11' "Cuenta $UsuarioApp existe en la base" $false 'no existe: el GRANT se omitio, revisar permisos manualmente' }
    else { Check 'P11' "$UsuarioApp solo SELECT sobre areas, eventos y vista (3); sin escritura ni acceso a auditoria" ($solo -eq 3 -and $otros -eq 0) "SELECT=$solo otros=$otros" }

    if ($pre) {
        $p = $pre.datos.estado
        $a = (Invoke-Filas $con @"
SELECT (SELECT COUNT_BIG(*) FROM dbo.registros_calidad_faret WHERE id <= @rmax) AS registros_orig,
       (SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM dbo.registros_calidad_faret WHERE id <= @rmax) AS registros_checksum,
       (SELECT COUNT_BIG(*) FROM dbo.registro_calidad_faret_defectos WHERE id <= @dmax) AS defectos_orig,
       (SELECT CHECKSUM_AGG(CHECKSUM(id, registro_id, defecto)) FROM dbo.registro_calidad_faret_defectos WHERE id <= @dmax) AS defectos_checksum,
       (SELECT COUNT(client_uuid) FROM dbo.registros_calidad_faret WHERE id <= @rmax) AS uuid_con_valor,
       (SELECT COUNT(DISTINCT client_uuid) FROM dbo.registros_calidad_faret WHERE id <= @rmax) AS uuid_distintos
"@ @{ '@rmax' = [int]$p.registros_max_id; '@dmax' = [int]$p.defectos_max_id })[0]
        Check 'P12' 'Inspecciones previas intactas (cantidad y checksum)' (([int64]$a.registros_orig -eq [int64]$p.registros) -and ($a.registros_checksum -eq $p.registros_checksum)) "antes=$($p.registros) ahora=$($a.registros_orig)"
        Check 'P13' 'Defectos historicos intactos (cantidad y checksum)' (([int64]$a.defectos_orig -eq [int64]$p.defectos) -and ($a.defectos_checksum -eq $p.defectos_checksum)) "antes=$($p.defectos) ahora=$($a.defectos_orig)"
        Check 'P14' 'client_uuid preservados' (($a.uuid_con_valor -eq $p.client_uuid_con_valor) -and ($a.uuid_distintos -eq $p.client_uuid_distintos)) "con valor=$($a.uuid_con_valor) distintos=$($a.uuid_distintos)"
    } else { Write-Log "No hay estado_previo reciente (<= $MaxHoras h): se omiten P12-P14." 'WARN' }
} finally { $con.Close() }

Save-Evidencia ("verificacion_posterior_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss')) ([ordered]@{ fecha = (Get-Date).ToString('s'); servidor = $info.servidor; base = $Base; fallos = $script:fallos; resultados = $script:resultados }) | Out-Null
if ($script:fallos -gt 0) { Write-Log "$($script:fallos) FALLO(S): no despliegue el backend. Vea RECUPERACION.md." 'ERROR'; exit 1 }
Write-Log 'TODAS las verificaciones pasaron. Base lista para el backend nuevo (Etapa 2).' 'OK'
