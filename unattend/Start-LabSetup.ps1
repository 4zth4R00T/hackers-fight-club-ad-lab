[CmdletBinding()]
param([Parameter(Mandatory)][string]$Source)

$ErrorActionPreference = 'Continue'
$cfgFile = Join-Path $Source 'config\lab.config.psd1'
$root = 'C:\Lab'
try {
    $raw = Import-PowerShellDataFile -LiteralPath $cfgFile
    if ($raw.Root) { $root = [string]$raw.Root }
} catch { }
if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
$null = & robocopy.exe $Source $root /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 /XF Start-LabSetup.ps1 autostart.txt
Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
Get-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
Get-NetConnectionProfile -ErrorAction SilentlyContinue | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
$log = Join-Path $root 'logs'
if (-not (Test-Path -LiteralPath $log)) { New-Item -ItemType Directory -Path $log -Force | Out-Null }
Add-Content -LiteralPath (Join-Path $log 'setup.log') -Value ('{0}  [OK   ] Kit copied from {1} to {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Source, $root)
if (Test-Path -LiteralPath (Join-Path $Source 'autostart.txt')) {
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'setup\Install-Lab.ps1') -Start
}
