@{
    Language           = 'auto'
    NamesLanguage      = 'auto'
    Organization       = 'Atlas Corp'
    LabName            = 'Hackers Fight Club'

    DomainPrefix       = 'fightclub'
    DomainSuffix       = 'lab'
    NetBIOSName        = 'FIGHTCLUB'
    DcHostPrefix       = 'DC'
    DcHostNumber       = 1
    ForestMode         = 'WinThreshold'
    DomainMode         = 'WinThreshold'

    Root               = 'C:\Lab'
    GroupPrefix        = 'Lab'
    FlagPrefix         = 'FLAG'
    StudentPrefix      = ''
    StudentSlots       = 100

    NetworkMode        = 'VMnet'
    LanInterface       = ''
    LanIPAddress       = '192.168.251.10'
    LanPrefixLength    = 24
    LanGateway         = '192.168.251.2'
    DnsForwarders      = @('192.168.251.2', '1.1.1.1', '9.9.9.9')
    TailscaleInterface = 'Tailscale'
    VpnInterface       = 'WireGuard*'
    VpnClientCidr      = '10.9.0.0/24'
    ExtraClientCidrs   = @()

    WebPort            = 8443
    IntranetPort       = 80
    BannerPort         = 1337
    SmtpPorts          = @(25, 587)
    Pop3Port           = 110

    MinPasswordLength  = 12
    LockoutThreshold   = 10
    TimeZone           = ''

    Wallpaper          = $true
    Challenges         = $true
    Mail               = $true
    Web                = $true

    Weaknesses         = @{
        ServiceAccountsWithSpn  = $true
        DirectoryNotes          = $true
        TokenInDnsSuffix        = $true
        SharedSmbAccount        = $true
        InternalHttpIntranet    = $true
        UnexpectedBannerPort    = $true
        PlaintextMail           = $true
        DelegatedSandboxOUs     = $true
        StudentsCreateGpos      = $true
        HighLockoutThreshold    = $true
    }
}
