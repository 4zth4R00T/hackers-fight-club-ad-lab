# Day 7 cheat sheet: administering the domain

## Managing objects

```powershell
New-ADUser -Name "a.test" -SamAccountName "a.test" -Enabled $true -AccountPassword (Read-Host -AsSecureString) -Path "OU=..."
Set-ADUser -Identity a.test -Description "..."
New-ADGroup -Name "MyGroup" -GroupScope Global -GroupCategory Security -Path "OU=..."
Add-ADGroupMember -Identity "MyGroup" -Members a.test
Get-ADGroupMember "MyGroup"
```

For bulk creation: a CSV and a `foreach`.

## The consoles

| Console | Command | Purpose |
|---|---|---|
| Users and Computers | `dsa.msc` | Users, groups, computers and OUs |
| Group Policy Management | `gpmc.msc` | Create, edit and link GPOs |
| DNS | `dnsmgmt.msc` | Zones and records |
| Event Viewer | `eventvwr.msc` | Where defenders find you |

## GPOs

| Half | Applies to |
|---|---|
| Computer configuration | The machine, at startup |
| User configuration | The person, at sign in |

Policies apply in this order: local, site, domain and OU. The last one applied wins, so the OU closest to the object rules. Two exceptions: **block inheritance** cuts the ones above and **enforced** wins no matter what.

```cmd
gpupdate /force
gpresult /r
```

### Security filtering

A GPO applies to whoever holds the **Apply group policy** permission. To target only one group, remove Authenticated Users and add the group with that permission. Linking a GPO and filtering it are two different things and you need both.

## Offense and its brakes

| Technique | Phase | Defense |
|---|---|---|
| Password spraying | Initial access | MFA, long passwords and detecting the pattern |
| Kerberoasting | Escalation | Managed accounts and long passwords on SPN accounts |
| Pass the hash | Lateral movement | LAPS, least privilege and less NTLM |
| Responder | Initial access | Disable LLMNR and NBT-NS, require SMB signing |
| Golden ticket | Domain | Protect the DC and rotate `krbtgt` |

**All of this only in your own labs or with explicit written authorization.** That is what separates a professional from a criminal.
