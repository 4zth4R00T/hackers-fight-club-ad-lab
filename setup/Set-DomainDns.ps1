[CmdletBinding()]
param([switch]$NoShow)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'LabAdmin.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

try {
    Import-Module DnsServer -ErrorAction Stop
    $c = Get-LabConfig
    $own = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
    $fw = @($c.DnsForwarders | Where-Object { $_ -and ($own -notcontains $_) })
    if ($fw.Count -gt 0) {
        Set-DnsServerForwarder -IPAddress $fw -UseRootHint $true
        Write-LabLog (L "Reenviadores DNS: $($fw -join ', ')" "DNS forwarders: $($fw -join ', ')") 'OK'
    } else {
        Write-LabLog (L 'Sin reenviadores: el DNS usara las sugerencias de raiz' 'No forwarders: DNS will use root hints') 'WARN'
    }

    $prefix = [int]$c.LanPrefixLength
    if ($prefix -ge 8 -and $prefix -le 24) {
        $octets = [int][Math]::Floor($prefix / 8)
        $net = (Get-NetworkCidr -Ip $c.LanIPAddress -Prefix ($octets * 8)).Split('/')[0].Split('.')
        $rev = (($net[0..($octets - 1)])[($octets - 1)..0] -join '.') + '.in-addr.arpa'
        if (-not (Get-DnsServerZone -Name $rev -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -NetworkId ('{0}/{1}' -f (($net[0..($octets - 1)] + @('0', '0', '0', '0'))[0..3] -join '.'), ($octets * 8)) -ReplicationScope Forest
            Write-LabLog (L "Zona inversa creada: $rev" "Reverse zone created: $rev") 'OK'
        }
        $hostPart = ($c.LanIPAddress.Split('.')[$octets..3])
        [array]::Reverse($hostPart)
        $ptrName = $hostPart -join '.'
        if (-not (Get-DnsServerResourceRecord -ZoneName $rev -Name $ptrName -RRType Ptr -ErrorAction SilentlyContinue)) {
            Add-DnsServerResourceRecordPtr -ZoneName $rev -Name $ptrName -PtrDomainName "$($c.DcFqdn)." -ErrorAction SilentlyContinue
        }
    }

    $pub = Update-DnsPublishing
    Write-LabLog (L "El dominio se publica en: $($pub -join ', ')" "The domain is published on: $($pub -join ', ')") 'OK'

    if ($c.NetworkMode -eq 'Tailscale' -or $c.NetworkMode -eq 'VPN') {
        if (-not (Get-ModeAddress)) {
            Write-LabLog (L "Todavia no hay interfaz $($c.NetworkMode). Cuando el tunel este arriba ejecuta setup\Set-NetworkMode.ps1 -Mode $($c.NetworkMode)" "There is no $($c.NetworkMode) interface yet. When the tunnel is up run setup\Set-NetworkMode.ps1 -Mode $($c.NetworkMode)") 'WARN'
        }
    }

    $test = Resolve-DnsName -Name $c.DomainFqdn -Server 127.0.0.1 -Type A -ErrorAction SilentlyContinue
    if ($test) { Write-LabLog (L "Resolucion local de $($c.DomainFqdn) correcta" "Local resolution of $($c.DomainFqdn) works") 'OK' }
    else { Write-LabLog (L "El DNS local todavia no resuelve $($c.DomainFqdn)" "Local DNS does not resolve $($c.DomainFqdn) yet") 'WARN' }
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
