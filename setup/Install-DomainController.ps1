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
    $role = (Get-CimInstance Win32_ComputerSystem).DomainRole
    if ($role -eq 4 -or $role -eq 5) {
        Write-LabLog (L 'Este servidor ya es controlador de dominio; no hay nada que hacer' 'This server is already a domain controller; nothing to do') 'OK'
        $Restart = $false
    } else {
        if ($env:COMPUTERNAME -ine $c.DcName) {
            throw (L "El servidor se llama $($env:COMPUTERNAME) y deberia llamarse $($c.DcName). Reinicia despues de Set-ServerNetwork.ps1." "The server is named $($env:COMPUTERNAME) and should be $($c.DcName). Reboot after Set-ServerNetwork.ps1.")
        }

        $features = @('AD-Domain-Services', 'DNS', 'GPMC', 'RSAT-AD-PowerShell', 'RSAT-ADDS', 'RSAT-DNS-Server')
        $missing = @($features | Where-Object { -not (Get-WindowsFeature -Name $_).Installed })
        if ($missing.Count -gt 0) {
            $r = Install-WindowsFeature -Name $missing -IncludeManagementTools
            if (-not $r.Success) { throw (L "No se pudieron instalar los roles: $($missing -join ', ')" "Could not install roles: $($missing -join ', ')") }
            Write-LabLog (L "Roles instalados: $($missing -join ', ')" "Roles installed: $($missing -join ', ')") 'OK'
        } else {
            Write-LabLog (L 'Los roles de AD DS y DNS ya estaban instalados' 'AD DS and DNS roles were already installed') 'OK'
        }

        $dsrm = Get-LabSecret -Name 'DsrmPassword'
        if (-not $dsrm) {
            $dsrm = New-RandomPassword -Length 24
            Set-LabSecret -Name 'DsrmPassword' -Value $dsrm
            Add-LabCredential -Kind 'DSRM' -Account "$($c.DcName)\DSRM" -Password $dsrm -Note (L 'Modo de restauracion de servicios de directorio' 'Directory Services Restore Mode')
        }

        Import-Module ADDSDeployment
        Write-LabLog (L "Creando el bosque $($c.DomainFqdn) con NetBIOS $($c.NetBIOSName). Tarda varios minutos." "Creating forest $($c.DomainFqdn) with NetBIOS $($c.NetBIOSName). This takes several minutes.") 'WARN'
        $r = Install-ADDSForest -DomainName $c.DomainFqdn -DomainNetbiosName $c.NetBIOSName `
            -ForestMode $c.ForestMode -DomainMode $c.DomainMode `
            -SafeModeAdministratorPassword (ConvertTo-SecureString $dsrm -AsPlainText -Force) `
            -InstallDns:$true -CreateDnsDelegation:$false `
            -DatabasePath "$env:SystemRoot\NTDS" -LogPath "$env:SystemRoot\NTDS" -SysvolPath "$env:SystemRoot\SYSVOL" `
            -NoRebootOnCompletion:$true -Force:$true -WarningAction SilentlyContinue
        if ($r.Status -ne 'Success') { throw "Install-ADDSForest: $($r.Status) $($r.Message)" }
        Write-LabLog (L "Bosque $($c.DomainFqdn) creado; falta reiniciar" "Forest $($c.DomainFqdn) created; reboot pending") 'OK'
        Write-LabLog (L "La clave DSRM quedo en $($c.Paths.Credentials). Copiala fuera del servidor." "The DSRM password is in $($c.Paths.Credentials). Copy it off the server.") 'WARN'
        Write-LabLog (L 'Siguiente paso tras reiniciar: Set-DomainDns.ps1' 'Next step after the reboot: Set-DomainDns.ps1')
    }
} catch {
    Write-LabLog $_.Exception.Message 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}
if (-not $NoShow) { Show-LabOutput }
if ($Restart) { Start-Sleep -Seconds 5; Restart-Computer -Force }
