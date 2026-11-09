[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Tailscale', 'VPN', 'VMnet', 'LAN')][string]$Mode,
    [string]$LanIPAddress,
    [int]$LanPrefixLength = 0,
    [string]$LanGateway,
    [string]$VpnInterface,
    [string]$VpnClientCidr,
    [switch]$ConnectTailscale,
    [switch]$NoShow
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lab.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'LabAdmin.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script como administrador.' 'Run this script as an administrator.') -ForegroundColor Red
    exit 1
}

function Set-ConfigValue {
    param([string]$Text, [string]$Key, [string]$Value)
    $pattern = "(?m)^(\s*$Key\s*=\s*).*$"
    if ($Text -match $pattern) { return [regex]::Replace($Text, $pattern, ('${1}' + $Value)) }
    return $Text.TrimEnd().TrimEnd('}') + "    $Key = $Value`r`n}`r`n"
}

try {
    $path = Get-LabConfigPath
    $old = Get-LabConfig
    $text = [IO.File]::ReadAllText($path)
    $text = Set-ConfigValue $text 'NetworkMode' "'$Mode'"
    if ($LanIPAddress) { $text = Set-ConfigValue $text 'LanIPAddress' "'$LanIPAddress'" }
    if ($LanPrefixLength -gt 0) { $text = Set-ConfigValue $text 'LanPrefixLength' "$LanPrefixLength" }
    if ($PSBoundParameters.ContainsKey('LanGateway')) { $text = Set-ConfigValue $text 'LanGateway' "'$LanGateway'" }
    if ($VpnInterface) { $text = Set-ConfigValue $text 'VpnInterface' "'$VpnInterface'" }
    if ($VpnClientCidr) { $text = Set-ConfigValue $text 'VpnClientCidr' "'$VpnClientCidr'" }
    [IO.File]::WriteAllText($path, $text, (New-Object Text.ASCIIEncoding))
    $c = Get-LabConfig -Reload
    Write-LabLog (L "Modo de red: $($old.NetworkMode) cambiado a $Mode" "Network mode: $($old.NetworkMode) changed to $Mode") 'OK'

    if ($Mode -eq 'Tailscale' -and $ConnectTailscale) {
        $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        if (-not (Test-Path -LiteralPath $ts)) {
            $msi = Join-Path $env:TEMP 'tailscale-setup.msi'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing
            $p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$msi`"", '/qn', 'TS_UNATTENDEDMODE=always') -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw (L "La instalacion de Tailscale devolvio $($p.ExitCode)" "The Tailscale installer returned $($p.ExitCode)") }
            Write-LabLog (L 'Tailscale instalado' 'Tailscale installed') 'OK'
        }
        $sec = Read-Host -AsSecureString (L 'Clave de autenticacion de Tailscale (Enter para iniciar sesion en el navegador)' 'Tailscale auth key (press Enter to sign in through the browser)')
        $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        $upArgs = @('up', '--unattended', '--accept-dns=false', ('--hostname=' + $c.DcName.ToLowerInvariant()))
        if ($key) { $upArgs += "--auth-key=$key" }
        & $ts @upArgs
        $key = $null
    }

    if ($Mode -eq 'LAN' -or $Mode -eq 'VMnet') {
        $nic = Get-LanAdapter
        if ($nic -and -not (Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $c.LanIPAddress -ErrorAction SilentlyContinue)) {
            Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Get-NetRoute -InterfaceIndex $nic.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
            $p = @{ InterfaceIndex = $nic.ifIndex; AddressFamily = 'IPv4'; IPAddress = $c.LanIPAddress; PrefixLength = [int]$c.LanPrefixLength }
            if ($c.LanGateway) { $p.DefaultGateway = $c.LanGateway }
            New-NetIPAddress @p | Out-Null
            Write-LabLog (L "Nueva IP del controlador: $($c.LanIPAddress)/$($c.LanPrefixLength)" "New controller IP: $($c.LanIPAddress)/$($c.LanPrefixLength)") 'OK'
        }
    }

    $addr = Get-ServiceAddress -TimeoutSeconds 60
    if (-not $addr) {
        Write-LabLog (L "No hay direccion para el modo $Mode todavia. Levanta el tunel o el adaptador y vuelve a ejecutar este script." "There is no address for $Mode mode yet. Bring up the tunnel or adapter and run this script again.") 'WARN'
    }

    $pub = Update-DnsPublishing
    Write-LabLog (L "El dominio se publica en: $($pub -join ', ')" "The domain is published on: $($pub -join ', ')") 'OK'
    $seed = Join-Path (Split-Path -Parent $PSScriptRoot) 'engine\Initialize-Challenges.ps1'
    if ($c.Challenges -and (Test-Path -LiteralPath $seed)) {
        & $seed -DnsOnly -NoShow
        Write-LabLog (L 'Registros DNS de los retos actualizados' 'Challenge DNS records updated') 'OK'
    }
    $n = Update-FirewallScope
    Write-LabLog (L "Reglas de firewall actualizadas: $n; clientes permitidos: $((Get-ClientCidrs) -join ', ')" "Firewall rules updated: $n; allowed clients: $((Get-ClientCidrs) -join ', ')") 'OK'

    if ([Environment]::GetEnvironmentVariable('LAB_BIND', 'Machine') -and $addr) {
        [Environment]::SetEnvironmentVariable('LAB_BIND', $addr, 'Machine')
        [Environment]::SetEnvironmentVariable('LAB_ALLOW', ((Get-ClientCidrs) -join ','), 'Machine')
    }
    $restarted = @()
    foreach ($t in @(Get-ScheduledTask -TaskName 'Lab-*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ne 'Lab-Install' -and $_.State -ne 'Disabled' })) {
        Stop-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue
        $restarted += $t.TaskName
    }
    if ($restarted.Count -gt 0) { Write-LabLog (L "Servicios reiniciados: $($restarted -join ', ')" "Services restarted: $($restarted -join ', ')") 'OK' }
    if ($addr) { Write-LabLog (L "Los servicios del laboratorio escuchan en $addr" "Lab services listen on $addr") 'OK' }
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
