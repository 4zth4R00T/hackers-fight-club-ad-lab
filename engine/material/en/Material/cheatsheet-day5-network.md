# Day 5 cheat sheet: the network

## Ports you will see again and again

| Port | Service | Purpose |
|---|---|---|
| 53 | DNS | Turning names into addresses |
| 80, 443 | HTTP, HTTPS | Web |
| 88 | Kerberos | Domain authentication |
| 110 | POP3 | Reading mail |
| 25, 587 | SMTP | Sending mail |
| 389, 636 | LDAP, LDAPS | Querying Active Directory |
| 445 | SMB | Files and printers |
| 3268 | Global catalog | Forest wide searches |
| 3389 | RDP | Remote desktop |
| 5985 | WinRM | Remote PowerShell |

If 445, 3389, 389 and 88 are open, there is Windows and there is a domain.

## Troubleshooting

| Command | Purpose |
|---|---|
| `ipconfig /all` | **Everything**: MAC, DNS, domain and suffixes. Many things only show up here |
| `ipconfig /flushdns` | Empties the name cache |
| `ping host` | Checks whether it answers, though a firewall may block it |
| `tracert host` | The route hop by hop |
| `nslookup name server` | Asks a specific DNS server |
| `netstat -ano` | Connections and listening ports with their PID |
| `arp -a` | Local network neighbors |
| `route print` | Routing table |

## PowerShell

```powershell
Test-NetConnection {DCFQDN} -Port 445
Resolve-DnsName {DCFQDN}
Resolve-DnsName _ldap._tcp.dc._msdcs.{DOMAIN} -Type SRV
Invoke-WebRequest http://server/ -UseBasicParsing
```

## SMB

```cmd
net use Z: \\server\share /user:{NETBIOS}\user password
dir Z:
net use Z: /delete
```

## Name resolution, in order

1. Cache
2. The `hosts` file
3. DNS

When DNS fails, Windows shouts across the network with LLMNR and NBT-NS, and that is where tools like Responder impersonate the target. That is why they get turned off.

> The `hosts` file does not publish SRV records. It works for single names, not for locating a domain controller.

## The two that open Active Directory

**LDAP (389)** is the language for querying the directory: every `Get-ADUser` is LDAP underneath. **Kerberos (88)** authenticates with tickets: when you sign in you get a **TGT**, and for each service you trade it for a **TGS**. Your password never travels.

```cmd
klist
```
