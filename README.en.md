<p align="center"><img src="assets/logo/hfc-logo-256.png" width="160" alt="Hackers Fight Club"></p>

<h1 align="center">Hackers Fight Club · Active Directory Lab</h1>

<p align="center">Windows Server 2025 · seven days of practice · per student flags · scoreboard website</p>

<p align="center"><a href="README.md">Versión en español</a> · <a href="README.ru.md">Версия на русском</a> · <a href="https://4zth4r00t.github.io/hackers-fight-club-ad-lab/en/">Project page</a></p>

This repository builds, from scratch, a Windows Server 2025 domain controller ready to teach Windows and Active Directory. The course spans seven days: the command prompt, the registry, NTFS, PowerShell, networking, directory enumeration and Group Policy. It ships with a scoreboard website, internal mail, an intranet, a wallpaper that shows the name of whoever signs in, and scripts to enroll students and instructors from a CSV file.

Built by Aztharot for the Hackers Fight Club. If it helps you, follow me on Instagram: [@its_aztharot.exe](https://instagram.com/its_aztharot.exe).

## Cutoff date

This lab was written and tested against what was known on **November 9, 2026**, on Windows Server 2025 build 26100.

The weaknesses in this lab come from configuration, not from unpatched bugs, but Windows changes with every cumulative update. A later update may close a behavior used here, change a default or add a new protection. Before you open the lab to a group, run `Test-Lab.ps1`, walk through every challenge yourself and confirm it still behaves as described. If something no longer reproduces, check the Microsoft release notes published after that date.

## Use notice

This environment is vulnerable on purpose. Run it only on an isolated network you control: a VMware virtual network, a private VPN or a training LAN. Never connect it to a production network and never expose it to the Internet. Flags, passwords and secrets are generated on every install, so the repository holds no answers.

## Minimum requirements

| Item | Minimum | Recommended |
|---|---|---|
| ISO | Windows Server 2025 Standard or Datacenter with Desktop Experience, build 26100. The 180 day evaluation works | The same, fully updated |
| ISO language | English (en-US), Spanish from Spain (es-ES) or Russian (ru-RU) | For Latin America use the es-ES ISO with the es-MX region |
| CPU | 2 vCPU, 64 bit | 4 vCPU |
| Memory | 4 GB | 8 GB, since the website runs on Node.js |
| Disk | 64 GB | 80 GB |
| Firmware | UEFI or BIOS | UEFI with Secure Boot |
| Network | One adapter | One on the lab network |
| Internet | During the install, to download Node.js | Offline, drop the `node-v*-x64.msi` installer in the `web` folder |

Student machines need Windows 10 or 11 Pro, Enterprise or Education, because the Home edition cannot join a domain, and Windows PowerShell 5.1.

The lab works the same on Windows Server in English, in Spanish from Spain, with a Latin American regional format or in Russian. The scripts never rely on the translated name of a group or account: they look them up by SID.

## What is inside

| Folder | Contents |
|---|---|
| `config` | `lab.config.psd1` with every setting and `staff.csv` with the fictional company staff |
| `setup` | The domain controller install steps and the CSV enrollment scripts |
| `engine` | The challenge catalog, flag seeding, the scorer and the integrity report |
| `services` | Intranet, unexpected port service, SMTP and POP3 mail, monitor and their registration |
| `web` | The website for scores, challenges, submissions, monitoring and attendance |
| `client` | What runs on the student machine and the dynamic wallpaper |
| `unattend` | The unattended install template and the answer ISO builders |
| `assets` | Club logo, base wallpaper and fonts with their license |
| `lang` | The Russian texts and names used by the server and student scripts |
| `examples` | Sample CSV files with fictional names, in Spanish, English and Russian |
| `site` | The project page, built with Astro and published with GitHub Pages |

## Configuration

Everything comes from `config/lab.config.psd1`. Edit it before you install.

| Key | Purpose | Default |
|---|---|---|
| `Language` | Language for messages and texts: `es`, `en`, `ru` or `auto` | `auto` |
| `NamesLanguage` | Language for OU, group, share and folder names: `es`, `en`, `ru`, or `auto` to follow `Language` | `auto` |
| `Organization` | Name of the fictional company | `Atlas Corp` |
| `LabName` | Visible name of the lab | `Hackers Fight Club` |
| `DomainPrefix` and `DomainSuffix` | Domain prefix and suffix. The sample values give `fightclub.lab` | `fightclub` and `lab` |
| `NetBIOSName` | Short domain name | `FIGHTCLUB` |
| `DcHostPrefix` and `DcHostNumber` | Domain controller prefix and number. The sample values give `DC01` | `DC` and `1` |
| `Root` | Lab folder on the server | `C:\Lab` |
| `GroupPrefix` | Prefix for the root OU and groups | `Lab` |
| `FlagPrefix` | Flag prefix, for example `FLAG{...}` | `FLAG` |
| `StudentPrefix` | Prefix for each student's permanent identifier | `alumno` in Spanish, `student` in English or Russian |
| `NetworkMode` | `Tailscale`, `VPN`, `VMnet` or `LAN` | `VMnet` |
| `LanIPAddress`, `LanPrefixLength`, `LanGateway` | Static IP of the controller on its local or virtual network | `192.168.251.10/24` |
| `DnsForwarders` | DNS servers the controller forwards anything outside the domain to | The VMware gateway and two public resolvers |
| `VpnInterface` and `VpnClientCidr` | Adapter and client network in VPN mode | `WireGuard*` and `10.9.0.0/24` |
| `ExtraClientCidrs` | Additional networks allowed to use the services | empty |
| `WebPort`, `IntranetPort`, `BannerPort`, `SmtpPorts`, `Pop3Port` | Service ports | 8443, 80, 1337, 25 and 587, 110 |
| `MinPasswordLength` and `LockoutThreshold` | Password policy | 12 and 10 |
| `TimeZone` | Windows time zone id, empty to leave it alone | empty |
| `Wallpaper`, `Challenges`, `Mail`, `Web` | Switches for each component | all on |
| `Weaknesses` | Switch for each deliberate weakness, explained below | all on |

With `auto`, the language follows the Windows language: a Russian server uses `ru`, a Spanish one uses `es` and anything else uses `en`. With `NamesLanguage` set to `ru`, OUs, groups, departments, roles and GPOs get Russian names, while shares, folders, kit files and mailboxes stay in Latin characters so they are easy to type in a console.

### Network modes

| Mode | When to use it | What it does |
|---|---|---|
| `VMnet` | The server and the student machines share one VMware virtual network | Services listen on the static IP and only accept that subnet |
| `LAN` | A classroom with physical machines on one network | Same as VMnet, on the classroom network |
| `Tailscale` | Students connect from home through a tailnet | Services listen on the Tailscale IP and only accept `100.64.0.0/10` |
| `VPN` | You run WireGuard, OpenVPN or another VPN of your own | Services listen on the VPN adapter IP and only accept `VpnClientCidr` |

The domain is always published on the static local IP. In Tailscale and VPN modes it is also published on the tunnel IP. You can switch modes at any time with `Set-NetworkMode.ps1`.

## Step by step install

### 1. Install Windows Server 2025

You have two options.

**With the answer ISO.** Build a small disc that holds the unattended install and the lab kit. From Linux:

```bash
./unattend/new-answer-iso.sh -p en-US -o lab-answers.iso
```

From Windows:

```powershell
.\unattend\New-AnswerIso.ps1 -Region en-US -OutFile .\lab-answers.iso
```

The region can be `en-US`, `es-MX`, `es-ES` or `ru-RU`. With `ru-RU` use the Russian Windows Server ISO: the keyboard defaults to English with Russian available, and the time zone is Moscow. It asks for the administrator password. With `-g` on Linux or `-GeneratePassword` on Windows it creates one and saves it next to the ISO in a file only you can read. With `-a` or `-AutoStart` the lab install starts by itself at the first sign in. Use `-f bios` or `-Firmware bios` if your virtual machine does not use UEFI.

Create the virtual machine with the original Windows Server 2025 ISO in the first CD drive and the answer ISO in the second. Windows installs without asking anything, names the server from your configuration and copies the kit to `C:\Lab`.

**By hand.** Install Windows Server 2025 with Desktop Experience, sign in as the administrator and copy the repository folder to `C:\Lab`.

### 2. Run the steps in order

Open PowerShell as an administrator and go to the setup folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd C:\Lab\setup
```

Run each script in this order. Every one prints a summary when it finishes and tells you which one comes next.

| Order | Command | What it does |
|---|---|---|
| 1 | `.\Set-ServerNetwork.ps1 -Restart` | Sets the static IP, creates the firewall rules, configures time and renames the server. Reboots |
| 2 | `.\Install-DomainController.ps1 -Restart` | Installs AD DS and DNS and creates the forest. Generates the DSRM password. Reboots |
| 3 | `.\Set-DomainDns.ps1` | Forwarders, reverse zone and the addresses the domain is published on |
| 4 | `.\New-DirectoryStructure.ps1` | OUs, groups, password policy, delegation, fictional staff, service accounts and computer inventory |
| 5 | `.\New-FileShares.ps1` | Home folders, public material, blind flag drop box and the confidential share |
| 6 | `.\Set-GroupPolicies.ps1` | Who may sign in to the controller and the dynamic wallpaper |
| 7 | `.\Protect-DomainController.ps1` | Controller hardening and auditing |
| 8 | `..\engine\Initialize-Challenges.ps1` | Creates the flag salt, seeds the challenges and prepares the kits |
| 9 | `.\Add-Administrators.ps1 -Path ..\config\administrators.csv` | Enrolls the instructors |
| 10 | `.\Add-Students.ps1 -Path ..\config\students.csv` | Enrolls the students and prepares their personal kit |
| 11 | `..\services\Register-Services.ps1` | Registers the intranet, unexpected port, mail, monitor and scorer |
| 12 | `..\web\Install-Web.ps1` | Installs Node.js, builds the website, creates the certificate and publishes it |
| 13 | `.\Test-Lab.ps1` | Checks everything and lists the enabled weaknesses |

If you would rather run it all in one go, `.\Install-Lab.ps1 -Start` runs the same sequence, survives the reboots and keeps going on its own. `.\Install-Lab.ps1` with no parameters shows where it is, and `-Resume` continues after you fix an error. If you placed the administrators and students CSV files inside `config` before you started, that run enrolls them too.

Generated passwords are stored in `C:\Lab\data`, readable only by SYSTEM and administrators. Copy the DSRM password and the administrator password off the server.

### 3. Join the student machines

On each machine, as a local administrator, run `client\Join-Lab.ps1`. With no parameters it only runs diagnostics. `-Prepare` sets DNS and networking for the selected mode, `-Join -User <username>` joins the machine to the domain in the workstations OU, and `-Leave` takes it out and puts everything back.

## CSV enrollment

The CSV files accept Spanish, English or Russian headers, separated by commas or semicolons, saved as UTF-8 or, when they come from a Russian Excel, as Windows-1251. Empty columns fill themselves in: the username is built from the first initial and the first surname, the email from the domain, and the password is generated. Cyrillic names are transliterated to Latin characters for the username, so Иван Петров becomes `i.petrov`.

Students, with `Add-Students.ps1`:

```csv
firstname,lastname,username,email,password,group
Avery,Sample One,,,,
Jordan,Sample Two,j.sample2,,,
```

Spanish equivalent: `nombre,apellidos,usuario,correo,contrasena,grupo`. Russian: `имя,фамилия,пользователь,почта,пароль,группа`.

Instructors and administrators, with `Add-Administrators.ps1`:

```csv
firstname,lastname,username,email,password,role
Instructor,Sample,adm.instructor,,,instructor
Domain,Sample,adm.domain,,,admin
```

The `instructor` role manages the lab OU through delegation and may use remote desktop, without being a domain admin. The `admin` role is also added to Domain Admins. A Russian CSV may use `преподаватель` and `администратор`. Every run leaves a CSV with the credentials in `C:\Lab\data`; delete it once you have handed them out.

Each student gets a permanent identifier (`student1`, `student2` and so on), a home folder on drive `H:`, an OU of their own under `Sandbox` with full control to practice, and their challenge kit. Personal flags derive from that identifier, so you can rename the account without invalidating anything.

## Dynamic wallpaper

Everyone who signs in to a domain machine, whether student, instructor or administrator, sees a wallpaper with the club logo, their full name, their role, their account, the machine and the date. It is rendered on the fly at every sign in, at the screen's resolution. If anything fails, the club's base wallpaper stays. The script lives in `NETLOGON\wallpaper` and the wallpaper GPO linked to the domain turns it on.

## The activities

Seven days, 36 challenges: 620 required points and 100 optional ones. The first person to solve a challenge earns 5 extra points, completing a day earns 25, and submitting someone else's flag costs 10.

| Day | Topic | What students practice |
|---|---|---|
| 1 | Getting to know Windows | Their own map of the core concepts |
| 2 | The command prompt | Environment variables, hidden files, searching inside files, PATH, scheduled tasks |
| 3 | Windows under the hood | Registry, NTFS alternate data streams, links and SIDs |
| 4 | Automating with PowerShell | Searching large logs, building structures, joining parts in order, exporting to CSV and JSON |
| 5 | The network and the full thread | Network settings, a DNS sweep, SMB with chained credentials, an unexpected port and internal mail |
| 6 | Active Directory | Enumerating users, groups, computers and accounts with an SPN |
| 7 | Administer and defend | Logon hours GPO, process auditing, a group filtered wallpaper, user creation and a writeup with a defense section |

Every day ends with a writeup. The challenges on days 4 and 7 that carry no flag are checked by the scorer, which reads the student's folder, their OU and SYSVOL.

The lab includes integrity controls: a different flag for every student, the NTFS owner of every submission, five decoys that only someone dumping whole files would find, and behavioral signals. The report comes from `engine\Get-IntegrityReport.ps1` and never shows on the public scoreboard. A decoy proves nothing on its own: it is a reason to talk with the person.

## Deliberate weaknesses

These are the weaknesses the lab leaves open on purpose. Each one can be turned off under `Weaknesses` in the configuration.

| Switch | Weakness | What it teaches |
|---|---|---|
| `ServiceAccountsWithSpn` | Service accounts with an SPN | Enumerating SPNs and understanding Kerberoasting. Their passwords are long and random, which is the defense |
| `DirectoryNotes` | Sensitive data in the Description and info attributes of users, computers and groups | That the directory holds more than a default listing shows |
| `TokenInDnsSuffix` | A secret distributed in the DNS suffix list by GPO | That the full network configuration reveals more than plain `ipconfig` |
| `SharedSmbAccount` | A shared SMB account whose password is that secret | Credential reuse and chaining clues |
| `InternalHttpIntranet` | A plaintext HTTP intranet with internal names | Automated DNS sweeps and reading HTML |
| `UnexpectedBannerPort` | A service listening where it should not | Port scanning and talking to an unknown service |
| `PlaintextMail` | SMTP and POP3 mail without TLS | Cleartext protocols and authentication exposed on the wire |
| `DelegatedSandboxOUs` | Students hold full control over their own OU | Delegation in AD and its risks |
| `StudentsCreateGpos` | Students in Group Policy Creator Owners | Creating and linking GPOs, and why that group is sensitive |
| `HighLockoutThreshold` | Account lockout after 10 attempts | Why a high threshold makes password spraying easier |

The delegation that lets students join computers to the workstations OU is a known risk too: anyone who can join machines there can reset the password of other machines in that OU.

What stays protected: the machine account quota is 0, students cannot sign in to the controller, instructors are not domain admins, the flag drop box is blind, each confidential record is readable only by its owner, the firewall blocks every inbound connection except the lab network, the print spooler and NetBIOS are off, LSA runs protected, WDigest keeps no cleartext credentials and advanced auditing is on. Process creation auditing stays off on purpose because it is a day 7 exercise.

## Operations

| Command | Purpose |
|---|---|
| `.\Install-Lab.ps1` | Install status |
| `.\Test-Lab.ps1` | Full check and enabled weaknesses |
| `.\Set-NetworkMode.ps1 -Mode Tailscale -ConnectTailscale` | Switch to Tailscale, install it and connect it |
| `.\Set-NetworkMode.ps1 -Mode LAN -LanIPAddress 10.0.0.10 -LanPrefixLength 24 -LanGateway 10.0.0.1` | Switch to a LAN with a new IP |
| `..\engine\Invoke-Scorer.ps1 -Rebuild` | Recompute every score |
| `..\engine\Get-IntegrityReport.ps1 -Student student7` | Integrity report for one person |
| `..\web\Install-Web.ps1 -Status` | Website, certificate and service status |
| `..\web\Install-Web.ps1 -Restart` | Restart the website |
| `..\services\Register-Services.ps1 -Remove` | Remove the lab services |

Logs are kept in `C:\Lab\logs`.

## Project page

The page lives in `site/` and is built with Astro. The `.github/workflows/pages.yml` workflow publishes it to GitHub Pages whenever something inside `site/` changes. To turn it on, open the repository Settings, then Pages, and under Source choose GitHub Actions. It ends up at `https://<your-user>.github.io/<repository-name>/` and is available in Spanish, English and Russian.

To preview it locally:

```bash
cd site
pnpm install
pnpm dev
```

## Credits

Built by Aztharot for the Hackers Fight Club.

Instagram: [@its_aztharot.exe](https://instagram.com/its_aztharot.exe) · GitHub: [4zth4R00T](https://github.com/4zth4R00T)

The Cormorant Garamond and IBM Plex Mono typefaces are distributed under the SIL Open Font License 1.1, included in `assets/fonts/OFL.txt`. The code is released under the MIT license.
