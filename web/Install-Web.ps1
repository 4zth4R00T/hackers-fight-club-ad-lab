[CmdletBinding()]
param(
    [switch]$NoShow,
    [switch]$Status,
    [switch]$Restart,
    [switch]$Rebuild,
    [switch]$Certificate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $RepoRoot 'setup\Lab.psm1') -DisableNameChecking

if (-not (Test-Administrator)) {
    Write-Host (L 'Ejecuta este script en una consola de PowerShell como administrador.' 'Run this script from an elevated PowerShell console.') -ForegroundColor Red
    exit 1
}

$TaskName = 'Lab-Web'
$RuleName = 'Lab-Web'

function Invoke-Quiet {
    param([Parameter(Mandatory)][scriptblock]$Block)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $Block) } finally { $ErrorActionPreference = $prev }
}

function Find-Node {
    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($p in @((Join-Path $env:ProgramFiles 'nodejs\node.exe'), (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'))) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function Install-Node {
    param([Parameter(Mandatory)][string]$WebDir)
    $local = Get-ChildItem -LiteralPath $WebDir -Filter 'node-v*-x64.msi' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    $msi = $null
    if ($local) {
        $msi = $local.FullName
        Write-LabLog (L "Instalador local de Node.js encontrado: $($local.Name)" "Local Node.js installer found: $($local.Name)")
    } else {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing -TimeoutSec 40
            $lts = @($index | Where-Object { $_.lts -and (@($_.files) -contains 'win-x64-msi') }) | Select-Object -First 1
            if (-not $lts) { throw 'index' }
            $msi = Join-Path $env:TEMP ('node-{0}-x64.msi' -f $lts.version)
            Write-LabLog (L "Descargando Node.js $($lts.version) LTS" "Downloading Node.js $($lts.version) LTS")
            Invoke-WebRequest -Uri ('https://nodejs.org/dist/{0}/node-{0}-x64.msi' -f $lts.version) -OutFile $msi -UseBasicParsing -TimeoutSec 900
        } catch {
            throw (L "No hay Node.js en este servidor y no se pudo descargar. Copia el instalador LTS de 64 bits (node-vXX.YY.Z-x64.msi, de nodejs.org) en la carpeta $WebDir y vuelve a ejecutar este paso." "Node.js is not installed and could not be downloaded. Copy the 64 bit LTS installer (node-vXX.YY.Z-x64.msi, from nodejs.org) into $WebDir and run this step again.")
        }
    }
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', ('"{0}"' -f $msi), '/qn', '/norestart') -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw (L "El instalador de Node.js termino con el codigo $($p.ExitCode)." "The Node.js installer exited with code $($p.ExitCode).")
    }
    Write-LabLog (L 'Node.js instalado.' 'Node.js installed.') 'OK'
}

function Invoke-Node {
    param([Parameter(Mandatory)][string]$Node, [Parameter(Mandatory)][string[]]$Arguments, [Parameter(Mandatory)][string]$WorkDir, [Parameter(Mandatory)][string]$Log)
    $o = [IO.Path]::GetTempFileName()
    $e = [IO.Path]::GetTempFileName()
    $quoted = @($Arguments | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } })
    try {
        $p = Start-Process -FilePath $Node -ArgumentList $quoted -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $o -RedirectStandardError $e
        $text = ([IO.File]::ReadAllText($o) + [IO.File]::ReadAllText($e))
        Add-Content -LiteralPath $Log -Value ("==== {0}  node {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($Arguments -join ' ')) -Encoding UTF8
        Add-Content -LiteralPath $Log -Value $text -Encoding UTF8
        return $p.ExitCode
    } finally {
        Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
    }
}

function Get-NpmCli {
    param([Parameter(Mandatory)][string]$Node)
    $cli = Join-Path (Split-Path -Parent $Node) 'node_modules\npm\bin\npm-cli.js'
    if (Test-Path -LiteralPath $cli) { return $cli }
    throw (L 'No se encontro npm junto a Node.js. Reinstala Node.js con sus componentes por defecto.' 'npm was not found next to Node.js. Reinstall Node.js with its default components.')
}

function Invoke-WebBuild {
    param([Parameter(Mandatory)][string]$Node, [Parameter(Mandatory)][string]$WebDir, [Parameter(Mandatory)][string]$Log)
    $env:Path = (Split-Path -Parent $Node) + ';' + $env:Path
    $env:NODE_ENV = $null
    $npm = Get-NpmCli -Node $Node
    $verb = 'install'
    if (Test-Path -LiteralPath (Join-Path $WebDir 'package-lock.json')) { $verb = 'ci' }
    Write-LabLog (L "Instalando dependencias de la web con npm $verb" "Installing web dependencies with npm $verb")
    $rc = Invoke-Node -Node $Node -Arguments @($npm, $verb, '--no-audit', '--no-fund', '--loglevel=error') -WorkDir $WebDir -Log $Log
    if ($rc -ne 0) { throw (L "npm $verb fallo con el codigo $rc. Revisa $Log" "npm $verb failed with code $rc. Check $Log") }
    Write-LabLog (L 'Compilando la web' 'Building the web app')
    $rc = Invoke-Node -Node $Node -Arguments @('build.mjs') -WorkDir $WebDir -Log $Log
    if ($rc -ne 0) { throw (L "La compilacion fallo con el codigo $rc. Revisa $Log" "The build failed with code $rc. Check $Log") }
    if (-not (Test-Path -LiteralPath (Join-Path $WebDir 'dist\server.js'))) { throw (L 'La compilacion no produjo dist\server.js.' 'The build did not produce dist\server.js.') }
    Write-LabLog (L 'Web compilada.' 'Web app built.') 'OK'
}

function Get-TlsAcceptCallback {
    if (-not ('LabTlsAccept' -as [type])) {
        Add-Type -TypeDefinition 'public static class LabTlsAccept { public static bool Accept(object a, System.Security.Cryptography.X509Certificates.X509Certificate b, System.Security.Cryptography.X509Certificates.X509Chain c, System.Net.Security.SslPolicyErrors d) { return true; } }'
    }
    return [Delegate]::CreateDelegate([Net.Security.RemoteCertificateValidationCallback], [LabTlsAccept].GetMethod('Accept'))
}

function Get-TlsThumbprint {
    param([Parameter(Mandatory)][string]$HostName, [Parameter(Mandatory)][int]$Port, [string]$ServerName)
    if (-not $ServerName) { $ServerName = $HostName }
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $iar = $tcp.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(5000)) { return $null }
        $tcp.EndConnect($iar)
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, (Get-TlsAcceptCallback))
        try {
            $ssl.AuthenticateAsClient($ServerName)
            return (New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)).Thumbprint
        } finally { $ssl.Dispose() }
    } catch { return $null } finally { $tcp.Close() }
}

function Test-DomainController {
    try { return ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) } catch { return $false }
}

function Enable-Ldaps {
    param([Parameter(Mandatory)]$Config)
    if (-not (Test-DomainController)) {
        Write-LabLog (L 'Este equipo no es controlador de dominio todavia: LDAPS se configura cuando lo sea.' 'This computer is not a domain controller yet: LDAPS will be configured once it is.') 'WARN'
        return
    }
    $fqdn = [string]$Config.DcFqdn
    $existing = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object {
        $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30) -and
        (@($_.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -contains '1.3.6.1.5.5.7.3.1') -and
        (@($_.DnsNameList | ForEach-Object { [string]$_.Unicode }) -contains $fqdn)
    } | Sort-Object NotAfter -Descending | Select-Object -First 1
    $cert = $existing
    if (-not $cert) {
        $names = @($fqdn, [string]$Config.DcName, [string]$Config.DomainFqdn) | Select-Object -Unique
        $san = '2.5.29.17={text}' + (($names | ForEach-Object { "DNS=$_" }) -join '&')
        $cert = New-SelfSignedCertificate -Subject "CN=$fqdn" -TextExtension @($san, '2.5.29.37={text}1.3.6.1.5.5.7.3.1') `
            -CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy NonExportable -KeyAlgorithm RSA -KeyLength 2048 `
            -HashAlgorithm SHA256 -KeyUsage DigitalSignature, KeyEncipherment -NotAfter (Get-Date).AddYears(3) -FriendlyName 'Lab LDAPS'
        Write-LabLog (L "Certificado LDAPS creado para $fqdn" "LDAPS certificate created for $fqdn") 'OK'
        $store = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
        $store.Open('ReadWrite')
        $store.Add([Security.Cryptography.X509Certificates.X509Certificate2]$cert)
        $store.Close()
        try {
            $rd = [ADSI]'LDAP://localhost/RootDSE'
            $rd.Put('renewServerCertificate', 1)
            $rd.SetInfo()
        } catch {
            Write-LabLog (L 'El directorio no acepto la recarga del certificado; se aplicara al reiniciar el servidor.' 'The directory did not accept the certificate reload; it will apply after a reboot.') 'WARN'
        }
    } else {
        Write-LabLog (L "LDAPS ya tiene certificado valido hasta $($cert.NotAfter.ToString('yyyy-MM-dd'))" "LDAPS already has a valid certificate until $($cert.NotAfter.ToString('yyyy-MM-dd'))") 'OK'
    }
    $thumb = $null
    for ($i = 0; $i -lt 12 -and -not $thumb; $i++) {
        $thumb = Get-TlsThumbprint -HostName '127.0.0.1' -Port 636 -ServerName $fqdn
        if (-not $thumb) { Start-Sleep -Seconds 5 }
    }
    $file = Join-Path $Config.Paths.WebData '.ldaps-thumbprint'
    if ($thumb) {
        [IO.File]::WriteAllText($file, $thumb, [Text.Encoding]::ASCII)
        Write-LabLog (L "LDAPS responde en 127.0.0.1:636 con la huella $thumb" "LDAPS answers on 127.0.0.1:636 with thumbprint $thumb") 'OK'
    } else {
        Write-LabLog (L 'LDAPS todavia no responde en 636. La web no podra validar sesiones hasta que responda; vuelve a ejecutar este paso en unos minutos.' 'LDAPS does not answer on 636 yet. The web app cannot validate sign ins until it does; run this step again in a few minutes.') 'WARN'
    }
}

function Get-CertFiles {
    param([Parameter(Mandatory)]$Config)
    $dir = Join-Path $Config.Paths.WebData 'certs'
    return @{
        Dir = $dir
        Crt = Join-Path $dir 'web.crt'
        Key = Join-Path $dir 'web.key'
        Pfx = Join-Path $dir 'web.pfx'
        Pass = Join-Path $dir 'web.pass'
        Origin = Join-Path $dir 'origin.txt'
    }
}

function Get-WebCertInfo {
    param([Parameter(Mandatory)]$Config)
    $f = Get-CertFiles -Config $Config
    $origin = 'none'
    if (Test-Path -LiteralPath $f.Origin) { $origin = ([IO.File]::ReadAllText($f.Origin)).Trim() }
    try {
        if ((Test-Path -LiteralPath $f.Crt) -and (Test-Path -LiteralPath $f.Key)) {
            $x = New-Object Security.Cryptography.X509Certificates.X509Certificate2($f.Crt)
            return [pscustomobject]@{ Present = $true; Origin = $origin; NotAfter = $x.NotAfter; Subject = $x.Subject }
        }
        if ((Test-Path -LiteralPath $f.Pfx) -and (Test-Path -LiteralPath $f.Pass)) {
            $pw = ([IO.File]::ReadAllText($f.Pass)).Trim()
            $x = New-Object Security.Cryptography.X509Certificates.X509Certificate2($f.Pfx, $pw)
            return [pscustomobject]@{ Present = $true; Origin = $origin; NotAfter = $x.NotAfter; Subject = $x.Subject }
        }
    } catch { }
    return [pscustomobject]@{ Present = $false; Origin = $origin; NotAfter = $null; Subject = '' }
}

function Get-TailscaleName {
    $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (-not (Test-Path -LiteralPath $ts)) { return $null }
    $json = Invoke-Quiet { & $ts status --json 2>$null | Out-String }
    try { $name = ([string]($json | ConvertFrom-Json).Self.DNSName).TrimEnd('.') } catch { $name = '' }
    if ($name) { return $name }
    return $null
}

function New-WebCertificate {
    param([Parameter(Mandatory)]$Config, [string]$Bind)
    $f = Get-CertFiles -Config $Config
    New-Folder $f.Dir | Out-Null
    if ($Config.NetworkMode -eq 'Tailscale') {
        $name = Get-TailscaleName
        if ($name) {
            $ts = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
            $out = Invoke-Quiet { & $ts cert --cert-file $f.Crt --key-file $f.Key $name 2>&1 | Out-String }
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $f.Crt)) {
                [IO.File]::WriteAllText($f.Origin, 'tailscale', [Text.Encoding]::ASCII)
                Remove-Item -LiteralPath $f.Pfx, $f.Pass -Force -ErrorAction SilentlyContinue
                Set-SecureAcl -Path $f.Dir
                Write-LabLog (L "Certificado publico de Tailscale emitido para $name" "Public Tailscale certificate issued for $name") 'OK'
                return $name
            }
            Write-LabLog (L "Tailscale no emitio certificado ($($out.Trim())). Activa MagicDNS y HTTPS Certificates en la consola del tailnet; mientras tanto se usa uno autofirmado." "Tailscale did not issue a certificate ($($out.Trim())). Enable MagicDNS and HTTPS Certificates in the tailnet console; a self signed one is used meanwhile.") 'WARN'
        }
    }
    $names = @([string]$Config.DcFqdn, [string]$Config.DcName, [string]$Config.DomainFqdn) | Where-Object { $_ } | Select-Object -Unique
    $ips = @($Bind, [string]$Config.LanIPAddress) | Where-Object { $_ } | Select-Object -Unique
    $parts = @($names | ForEach-Object { "DNS=$_" }) + @($ips | ForEach-Object { "IPAddress=$_" })
    $san = '2.5.29.17={text}' + ($parts -join '&')
    $cert = New-SelfSignedCertificate -Subject ("CN={0}" -f $Config.DcFqdn) -TextExtension @($san, '2.5.29.37={text}1.3.6.1.5.5.7.3.1') `
        -CertStoreLocation 'Cert:\LocalMachine\My' -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 `
        -HashAlgorithm SHA256 -KeyUsage DigitalSignature, KeyEncipherment -NotAfter (Get-Date).AddYears(2) -FriendlyName 'Lab web'
    $pass = New-RandomPassword -Length 32
    $sec = ConvertTo-SecureString $pass -AsPlainText -Force
    try {
        Export-PfxCertificate -Cert $cert -FilePath $f.Pfx -Password $sec -CryptoAlgorithmOption AES256_SHA256 | Out-Null
    } catch [System.Management.Automation.ParameterBindingException] {
        Export-PfxCertificate -Cert $cert -FilePath $f.Pfx -Password $sec | Out-Null
    }
    [IO.File]::WriteAllText($f.Pass, $pass, [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($f.Origin, 'self-signed', [Text.Encoding]::ASCII)
    Remove-Item -LiteralPath ('Cert:\LocalMachine\My\' + $cert.Thumbprint) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $f.Crt, $f.Key -Force -ErrorAction SilentlyContinue
    Set-SecureAcl -Path $f.Dir
    Write-LabLog (L "Certificado autofirmado creado para $($names -join ', ') y $($ips -join ', '). El navegador avisara la primera vez." "Self signed certificate created for $($names -join ', ') and $($ips -join ', '). Browsers will warn on the first visit.") 'OK'
    return $null
}

function Get-StudentCommands {
    param([Parameter(Mandatory)]$Config)
    $map = @{ '{CMD_CHALLENGES}' = 'Get-Challenges'; '{CMD_HINT}' = 'Get-Hint'; '{CMD_SUBMIT}' = 'Submit-Flag'; '{CMD_PROGRESS}' = 'Get-Progress'; '{CMD_MAIL}' = 'Send-LabMail' }
    $mod = Join-Path $Config.Paths.Client 'Student.psm1'
    if (-not (Test-Path -LiteralPath $mod)) { return $map }
    $names = @(Select-String -LiteralPath $mod -Pattern '^\s*function\s+([A-Za-z]+-[A-Za-z0-9]+)' -AllMatches | ForEach-Object { $_.Matches[0].Groups[1].Value })
    $rules = @(
        @{ Key = '{CMD_SUBMIT}'; Pattern = '^Submit-.*Flag' }
        @{ Key = '{CMD_HINT}'; Pattern = '(Hint|Pista)' }
        @{ Key = '{CMD_PROGRESS}'; Pattern = '(Progress|Progreso)' }
        @{ Key = '{CMD_CHALLENGES}'; Pattern = '^Get-.*(Challenge|Reto)' }
        @{ Key = '{CMD_MAIL}'; Pattern = '^Send-.*(Mail|Correo)' }
    )
    foreach ($r in $rules) {
        $hit = $names | Where-Object { $_ -match $r.Pattern } | Select-Object -First 1
        if ($hit) { $map[$r.Key] = $hit }
    }
    return $map
}

function Write-SiteFile {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][hashtable]$Settings)
    $ph = @{}
    $expander = 'Expand-LabText'
    $engine = Join-Path $Config.Paths.Engine 'Challenges.psm1'
    if (Test-Path -LiteralPath $engine) {
        try {
            Import-Module $engine -DisableNameChecking -ErrorAction Stop
            if (Get-Command Expand-EngineText -ErrorAction SilentlyContinue) { $expander = 'Expand-EngineText' }
        } catch {
            Write-LabLog (L "No se pudo cargar el motor de retos para leer sus nombres: $($_.Exception.Message)" "The challenge engine could not be loaded to read its names: $($_.Exception.Message)") 'WARN'
        }
    }
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($k in @('{ORG}', '{LAB}', '{DOMAIN}', '{NETBIOS}', '{DC}', '{DCFQDN}', '{FLAG}', '{GROUP_PREFIX}', '{STUDENT_PREFIX}',
            '{ODD_GROUP}', '{SHARE_HOME}', '{SHARE_PUBLIC}', '{SHARE_DROPBOX}', '{SHARE_CONFIDENTIAL}', '{OU_SANDBOX}',
            '{WEB_PORT}', '{INTRANET_PORT}', '{BANNER_PORT}', '{KIT_DIR}', '{DELIVER_DIR}', '{WORK_DIR}', '{TEMPLATES_DIR}', '{MAIL_DIR}')) {
        $tokens.Add($k)
    }
    foreach ($file in @($Config.Paths.Catalog, (Join-Path $Config.Paths.Web 'content\ruta.json'), (Join-Path $Config.Paths.Content 'ruta.json'))) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($file), '\{[A-Z][A-Z0-9_]*\}')) {
            if (-not $tokens.Contains($m.Value)) { $tokens.Add($m.Value) }
        }
    }
    foreach ($k in $tokens) {
        $v = $null
        try { $v = [string](& $expander $k) } catch { $v = $null }
        if ($v -and $v -ne $k) { $ph[$k] = $v }
    }
    if (-not $ph.ContainsKey('{KIT_DIR}')) { $ph['{KIT_DIR}'] = '{0}-Kit' -f $Config.GroupPrefix }
    $cmds = Get-StudentCommands -Config $Config
    foreach ($k in $cmds.Keys) { $ph[$k] = $cmds[$k] }
    $report = Get-ChildItem -LiteralPath $Config.Paths.Engine -Filter '*Integrity*.ps1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($report) { $ph['{CMD_REPORT}'] = $report.FullName }
    $site = [ordered]@{
        Generated = (Get-Date).ToString('s')
        Settings = $Settings
        Placeholders = $ph
    }
    $path = Join-Path $Config.Paths.WebData 'site.json'
    Write-JsonFile -Path $path -Object $site
    Set-SecureAcl -Path $path
}

function Stop-WebProcess {
    param([Parameter(Mandatory)][string]$ServerJs)
    Invoke-Quiet { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } | Out-Null
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($ServerJs, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($procs.Count -gt 0) { Start-Sleep -Seconds 2 }
}

function Test-Listening {
    param([Parameter(Mandatory)][string]$Bind, [Parameter(Mandatory)][int]$Port)
    return (@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq $Bind -or $_.LocalAddress -eq '0.0.0.0' }).Count -gt 0)
}

function Wait-Listening {
    param([Parameter(Mandatory)][string]$Bind, [Parameter(Mandatory)][int]$Port, [int]$Seconds = 90)
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        if (Test-Listening -Bind $Bind -Port $Port) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Test-Health {
    param([Parameter(Mandatory)][string]$Bind, [Parameter(Mandatory)][int]$Port, [bool]$Tls)
    $scheme = 'http'
    if ($Tls) { $scheme = 'https' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $prev = [Net.ServicePointManager]::ServerCertificateValidationCallback
    [Net.ServicePointManager]::ServerCertificateValidationCallback = Get-TlsAcceptCallback
    try {
        foreach ($route in @('/salud', '/')) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try {
                $r = Invoke-WebRequest -Uri ('{0}://{1}:{2}{3}' -f $scheme, $Bind, $Port, $route) -UseBasicParsing -TimeoutSec 30
                Write-LabLog ('{0,-7} HTTP {1}  {2} ms' -f $route, $r.StatusCode, $sw.ElapsedMilliseconds) 'OK'
            } catch {
                Write-LabLog ('{0,-7} {1}' -f $route, $_.Exception.Message.Split("`n")[0]) 'WARN'
            }
        }
    } finally {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = $prev
    }
}

function Get-WebUrl {
    param([Parameter(Mandatory)]$Config, [string]$TailscaleName)
    $port = [int]$Config.WebPort
    if ($TailscaleName) { return ('https://{0}:{1}' -f $TailscaleName, $port) }
    $info = Get-WebCertInfo -Config $Config
    if ($info.Origin -eq 'tailscale') {
        $n = Get-TailscaleName
        if ($n) { return ('https://{0}:{1}' -f $n, $port) }
    }
    return ('https://{0}:{1}' -f $Config.DcFqdn, $port)
}

function Show-Status {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$WebDir, [string]$Bind)
    $node = Find-Node
    if ($node) {
        $v = Invoke-Quiet { & $node --version 2>$null | Out-String }
        Write-LabLog (L "Node.js $($v.Trim()) en $node" "Node.js $($v.Trim()) at $node") 'OK'
    } else {
        Write-LabLog (L 'Node.js no esta instalado.' 'Node.js is not installed.') 'WARN'
    }
    if (Test-Path -LiteralPath (Join-Path $WebDir 'dist\server.js')) { Write-LabLog (L 'La web esta compilada.' 'The web app is built.') 'OK' }
    else { Write-LabLog (L 'La web no esta compilada.' 'The web app is not built.') 'WARN' }
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) { Write-LabLog (L "Tarea $TaskName en estado $($task.State)" "Task $TaskName is $($task.State)") 'INFO' }
    else { Write-LabLog (L "La tarea $TaskName no existe." "Task $TaskName does not exist.") 'WARN' }
    $info = Get-WebCertInfo -Config $Config
    if ($info.Present) {
        $days = [int]($info.NotAfter - (Get-Date)).TotalDays
        $lvl = 'OK'
        if ($days -lt 30) { $lvl = 'WARN' }
        Write-LabLog (L "Certificado $($info.Origin), caduca en $days dias ($($info.NotAfter.ToString('yyyy-MM-dd')))" "Certificate $($info.Origin), expires in $days days ($($info.NotAfter.ToString('yyyy-MM-dd')))") $lvl
    } else {
        Write-LabLog (L 'No hay certificado: la web serviria HTTP sin cifrar.' 'No certificate: the web app would serve plain HTTP.') 'WARN'
    }
    $pin = Join-Path $Config.Paths.WebData '.ldaps-thumbprint'
    if (Test-Path -LiteralPath $pin) { Write-LabLog (L "Huella LDAPS anclada: $(([IO.File]::ReadAllText($pin)).Trim())" "Pinned LDAPS thumbprint: $(([IO.File]::ReadAllText($pin)).Trim())") 'INFO' }
    else { Write-LabLog (L 'Sin huella LDAPS anclada.' 'No pinned LDAPS thumbprint.') 'WARN' }
    if ($Bind) {
        if (Test-Listening -Bind $Bind -Port ([int]$Config.WebPort)) {
            Write-LabLog (L "Escuchando en ${Bind}:$($Config.WebPort)" "Listening on ${Bind}:$($Config.WebPort)") 'OK'
            Test-Health -Bind $Bind -Port ([int]$Config.WebPort) -Tls $info.Present
        } else {
            Write-LabLog (L "Nada escucha en ${Bind}:$($Config.WebPort)" "Nothing is listening on ${Bind}:$($Config.WebPort)") 'WARN'
        }
    }
}

try {
    $c = Get-LabConfig
    $webDir = [string]$c.Paths.Web
    if (-not (Test-Path -LiteralPath (Join-Path $webDir 'package.json'))) { $webDir = $PSScriptRoot }
    $logBuild = Join-Path $c.Paths.Logs 'web-build.log'
    $serverJs = Join-Path $webDir 'dist\server.js'
    New-Folder $c.Paths.Logs | Out-Null
    New-Folder $c.Paths.WebData | Out-Null
    Set-SecureAcl -Path $c.Paths.Data
    Set-SecureAcl -Path $c.Paths.WebData

    Add-LabOutput ''
    Add-LabOutput (L '  WEB DEL LABORATORIO' '  LAB WEB APP') 'TITLE'
    Add-LabOutput ('  ' + ('=' * 58)) 'TITLE'

    if ($c.ContainsKey('Web') -and -not [bool]$c.Web) {
        Write-LabLog (L 'La web esta desactivada en la configuracion (Web = $false). No se hace nada.' 'The web app is disabled in the configuration (Web = $false). Nothing to do.') 'WARN'
    }
    elseif ($Status) {
        Show-Status -Config $c -WebDir $webDir -Bind (Get-ServiceAddress -TimeoutSeconds 5)
    }
    else {
        $bind = Get-ServiceAddress -TimeoutSeconds 120
        if (-not $bind) {
            throw (L "No hay direccion de servicio para el modo de red $($c.NetworkMode). Revisa la red con setup\Set-NetworkMode.ps1." "There is no service address for network mode $($c.NetworkMode). Check the network with setup\Set-NetworkMode.ps1.")
        }
        Write-LabLog (L "Modo de red $($c.NetworkMode): la web escuchara en $bind" "Network mode $($c.NetworkMode): the web app will listen on $bind") 'INFO'

        $full = -not ($Restart -or $Rebuild -or $Certificate)
        $node = Find-Node
        if (-not $node) {
            if ($Restart) { throw (L 'Node.js no esta instalado. Ejecuta este paso sin parametros.' 'Node.js is not installed. Run this step without parameters.') }
            Install-Node -WebDir $webDir
            $node = Find-Node
            if (-not $node) { throw (L 'Node.js se instalo pero no aparece node.exe.' 'Node.js was installed but node.exe cannot be found.') }
        }

        if ($full -or $Rebuild -or -not (Test-Path -LiteralPath $serverJs)) {
            Stop-WebProcess -ServerJs $serverJs
            Invoke-WebBuild -Node $node -WebDir $webDir -Log $logBuild
        }

        $tsName = $null
        $info = Get-WebCertInfo -Config $c
        $needCert = $Certificate -or (-not $info.Present) -or ($info.NotAfter -and $info.NotAfter -lt (Get-Date).AddDays(30))
        if ($needCert) { $tsName = New-WebCertificate -Config $c -Bind $bind }

        if ($full) { Enable-Ldaps -Config $c }

        $drop = Join-Path $c.Paths.Score 'drop-web'
        New-Folder $drop | Out-Null
        Set-SecureAcl -Path $drop
        New-Folder $c.Paths.Content | Out-Null

        $cidrs = @(Get-ClientCidrs)
        $settings = [ordered]@{
            LAB_ROOT = [string]$c.Paths.Root
            LAB_WEB = $webDir
            LAB_BIND = $bind
            LAB_PORT = [string]$c.WebPort
            LAB_ALLOW = ($cidrs -join ',')
            LAB_DOMAIN = [string]$c.DomainFqdn
            LAB_NETBIOS = [string]$c.NetBIOSName
            LAB_LANG = [string]$c.Language
            LAB_ORG = [string]$c.Organization
            LAB_NAME = [string]$c.LabName
            LAB_INSTRUCTORS = (@($c.Groups.Instructors, $c.Groups.LabAdmins) | Where-Object { $_ }) -join ','
            LAB_LDAP = 'ldaps://127.0.0.1:636'
            LAB_FLAG = [string]$c.FlagPrefix
            LAB_CATALOG = [string]$c.Paths.Catalog
        }
        foreach ($k in $settings.Keys) { [Environment]::SetEnvironmentVariable($k, [string]$settings[$k], 'Machine') }
        Write-SiteFile -Config $c -Settings $settings
        Write-LabLog (L "Variables LAB_* fijadas a nivel de equipo; clientes permitidos: $($cidrs -join ', ')" "Machine level LAB_* variables set; allowed clients: $($cidrs -join ', ')") 'OK'

        Set-LabFirewallRule -Name $RuleName -Port ([string]$c.WebPort) -RemoteAddress $cidrs
        Write-LabLog (L "Regla de firewall $RuleName abierta en $($c.WebPort)/tcp solo para $($cidrs -join ', ')" "Firewall rule $RuleName opens $($c.WebPort)/tcp only for $($cidrs -join ', ')") 'OK'

        Stop-WebProcess -ServerJs $serverJs
        $args = '"{0}" --root "{1}"' -f $serverJs, $c.Paths.Root
        Register-LabTask -Name $TaskName -Execute $node -Arguments $args -AtStartup -Start `
            -Description (L 'Web del laboratorio: clasificacion, retos, entregas y monitor.' 'Lab web app: scoreboard, challenges, submissions and monitor.')
        Write-LabLog (L "Tarea $TaskName registrada y en marcha" "Task $TaskName registered and started") 'OK'

        if (Wait-Listening -Bind $bind -Port ([int]$c.WebPort) -Seconds 90) {
            Write-LabLog (L "Escuchando en ${bind}:$($c.WebPort)" "Listening on ${bind}:$($c.WebPort)") 'OK'
        } else {
            Write-LabLog (L "La web no abrio el puerto a tiempo. Revisa $(Join-Path $c.Paths.Logs 'web.log')" "The web app did not open its port in time. Check $(Join-Path $c.Paths.Logs 'web.log')") 'WARN'
        }
        $info = Get-WebCertInfo -Config $c
        Test-Health -Bind $bind -Port ([int]$c.WebPort) -Tls $info.Present

        $url = Get-WebUrl -Config $c -TailscaleName $tsName
        Set-LabSecret -Name 'WebUrl' -Value $url
        Add-LabOutput ''
        Add-LabOutput (L "  Direccion para alumnos e instructores: $url" "  Address for students and instructors: $url") 'OK'
        if ($info.Origin -ne 'tailscale') {
            Add-LabOutput (L "  Los equipos cliente deben resolver $($c.DcFqdn) con el DNS del dominio. El certificado es autofirmado: el navegador avisara la primera vez." "  Client machines must resolve $($c.DcFqdn) through the domain DNS. The certificate is self signed: browsers will warn on the first visit.") 'TEXT'
        }
    }
}
catch {
    Write-LabLog ($_.Exception.Message) 'ERROR'
    if ($NoShow) { throw }
    Show-LabOutput
    exit 1
}

if (-not $NoShow) { Show-LabOutput }
