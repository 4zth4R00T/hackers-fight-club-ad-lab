[CmdletBinding()]
param([switch]$NoShow, [switch]$Restart)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

try {
    $c = Get-LabConfig
    $nic = Get-LanAdapter
    if (-not $nic) {
        $names = (Get-NetAdapter | ForEach-Object { $_.Name }) -join ', '
        throw (L "No encontre el adaptador de red del laboratorio. Adaptadores: $names. Fija LanInterface en la configuracion." "Could not find the lab network adapter. Adapters: $names. Set LanInterface in the configuration.")
    }
    Write-LabLog (L "Adaptador del laboratorio: $($nic.Name)" "Lab adapter: $($nic.Name)")

    $current = Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $c.LanIPAddress -and $_.PrefixOrigin -eq 'Manual' }
    if ($current) {
        Write-LabLog (L "La IP fija $($c.LanIPAddress) ya estaba aplicada" "Static IP $($c.LanIPAddress) was already set") 'OK'
    } else {
        Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
        $p = @{ InterfaceIndex = $nic.ifIndex; AddressFamily = 'IPv4'; IPAddress = $c.LanIPAddress; PrefixLength = [int]$c.LanPrefixLength }
        if ($c.LanGateway) { $p.DefaultGateway = $c.LanGateway }
        New-NetIPAddress @p | Out-Null
        Write-LabLog (L "IP fija $($c.LanIPAddress)/$($c.LanPrefixLength) aplicada" "Static IP $($c.LanIPAddress)/$($c.LanPrefixLength) applied") 'OK'
    }

    $dns = @($c.DnsForwarders | Where-Object { $_ })
    if ($dns.Count -eq 0 -and $c.LanGateway) { $dns = @($c.LanGateway) }
    if ($dns.Count -gt 0) {
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $dns
        Write-LabLog (L "DNS provisional: $($dns -join ', ')" "Temporary DNS: $($dns -join ', ')")
    }

    if ($c.TimeZone) {
        try {
            Set-TimeZone -Id $c.TimeZone
            Write-LabLog (L "Zona horaria: $($c.TimeZone)" "Time zone: $($c.TimeZone)") 'OK'
        } catch {
            Write-LabLog (L "Zona horaria no valida: $($c.TimeZone)" "Invalid time zone: $($c.TimeZone)") 'WARN'
        }
    }

    $rules = @(
        @{ N = 'Lab-DNS-TCP';      P = 'TCP'; Port = '53' }
        @{ N = 'Lab-DNS-UDP';      P = 'UDP'; Port = '53' }
        @{ N = 'Lab-Kerberos-TCP'; P = 'TCP'; Port = '88' }
        @{ N = 'Lab-Kerberos-UDP'; P = 'UDP'; Port = '88' }
        @{ N = 'Lab-KPasswd-TCP';  P = 'TCP'; Port = '464' }
        @{ N = 'Lab-KPasswd-UDP';  P = 'UDP'; Port = '464' }
        @{ N = 'Lab-RPC-EPM';      P = 'TCP'; Port = '135' }
        @{ N = 'Lab-LDAP';         P = 'TCP'; Port = '389' }
        @{ N = 'Lab-LDAP-UDP';     P = 'UDP'; Port = '389' }
        @{ N = 'Lab-LDAPS';        P = 'TCP'; Port = '636' }
        @{ N = 'Lab-GC';           P = 'TCP'; Port = '3268' }
        @{ N = 'Lab-GC-TLS';       P = 'TCP'; Port = '3269' }
        @{ N = 'Lab-SMB';          P = 'TCP'; Port = '445' }
        @{ N = 'Lab-NTP';          P = 'UDP'; Port = '123' }
        @{ N = 'Lab-RPC-Dynamic';  P = 'TCP'; Port = '49152-65535' }
        @{ N = 'Lab-RDP';          P = 'TCP'; Port = '3389' }
        @{ N = 'Lab-WinRM';        P = 'TCP'; Port = '5985' }
    )
    $cidrs = Get-ClientCidrs
    $lan = Get-NetworkCidr -Ip $c.LanIPAddress -Prefix ([int]$c.LanPrefixLength)
    $adCidrs = @($cidrs)
    if ($adCidrs -notcontains $lan) { $adCidrs += $lan }
    foreach ($r in $rules) {
        Set-LabFirewallRule -Name $r.N -Port $r.Port -Protocol $r.P -RemoteAddress $adCidrs
    }
    if (Get-NetFirewallRule -Name 'Lab-Ping' -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -Name 'Lab-Ping' }
    New-NetFirewallRule -Name 'Lab-Ping' -DisplayName 'Lab-Ping' -Group 'Lab' -Direction Inbound -Action Allow `
        -Protocol ICMPv4 -IcmpType 8 -RemoteAddress $adCidrs -Profile Any | Out-Null
    Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow
    Write-LabLog (L "Firewall: $($rules.Count + 1) reglas de entrada para $($adCidrs -join ', '), el resto bloqueado" "Firewall: $($rules.Count + 1) inbound rules for $($adCidrs -join ', '), everything else blocked") 'OK'

    $null = & w32tm.exe /config /manualpeerlist:"pool.ntp.org,0x8 time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update
    Restart-Service w32time -ErrorAction SilentlyContinue
    Write-LabLog (L 'Servicio de hora configurado como fuente confiable del bosque' 'Time service set as the reliable source for the forest') 'OK'

    if ($env:COMPUTERNAME -ieq $c.DcName) {
        Write-LabLog (L "El servidor ya se llama $($c.DcName)" "The server is already named $($c.DcName)") 'OK'
    } else {
        Rename-Computer -NewName $c.DcName -Force
        Write-LabLog (L "Servidor renombrado de $($env:COMPUTERNAME) a $($c.DcName); se aplica al reiniciar" "Server renamed from $($env:COMPUTERNAME) to $($c.DcName); it applies after reboot") 'OK'
    }
    Write-LabLog (L 'Siguiente paso tras reiniciar: Install-DomainController.ps1' 'Next step after the reboot: Install-DomainController.ps1')
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
if ($Restart) { Start-Sleep -Seconds 5; Restart-Computer -Force }
