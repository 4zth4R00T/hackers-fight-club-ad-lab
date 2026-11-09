# Connection and submissions

How to get in, what you have mounted and **how the server knows you finished each activity**. The three kinds of challenge are tracked differently and none of them warns you: if you do the work in the wrong place, it does not score.

## 1. Reaching the lab

The domain controller is `{DCFQDN}`. Your instructor picked one of these four ways to reach it:

| Mode | What your computer needs |
|---|---|
| Tailscale | Tailscale installed and signed in to the course network. `Join-Lab.ps1 -Prepare` sets the tunnel to unattended mode so it comes up before you sign in |
| VPN | The VPN client (WireGuard, OpenVPN or another) connected before you sign in to Windows |
| VMnet | Your virtual machine on the same VMware virtual network as the server |
| LAN | Your computer on the same local network as the server |

In all four cases the script does the same thing: it creates an NRPT rule so that only `{DOMAIN}` queries go to the lab DNS and the rest of your browsing stays as it was.

```powershell
.\Join-Lab.ps1                                   # checks, changes nothing
.\Join-Lab.ps1 -Prepare                          # gets the computer ready
.\Join-Lab.ps1 -Join -User first.last            # prepares and joins
.\Join-Lab.ps1 -Leave -User first.last           # undoes everything
```

**Wait for the network before typing your password.** If you sign in without a connection to the lab, Windows does not fail: it lets you in with cached credentials. But you get no Kerberos ticket, no `H:` and nothing you do gets recorded. To check that your session is real:

```powershell
klist                    # krbtgt must show up
Get-Progress             # if it answers, you are really in
```

## 2. Your slot

Your account is `first.last`, but the lab also identifies you with a **slot**: `{STUDENT_PREFIX}1`, `{STUDENT_PREFIX}2` and so on. They are two names for the same person and you need both.

```powershell
(Get-Item H:).Target      # the last part of the path is your slot
```

Write it down. You need it on day 7.

## 3. What you have mounted

| What | Where | You can |
|---|---|---|
| Your home folder | `H:` at `\\{DC}\{SHARE_HOME}\<slot>` | Read and write |
| Your deliverables | `H:\{DELIVER_DIR}` | Read and write |
| Your lab | `%USERPROFILE%\{KIT_DIR}` | Read and write |
| Course material | `\\{DC}\{SHARE_PUBLIC}` | Read only |
| Flag dropbox | `\\{DC}\{SHARE_DROPBOX}` | Write only |
| Your mail | `H:\{MAIL_DIR}\Inbox` | Read and write |
| The scoreboard | {WEB_URL} | View and submit |

The flag dropbox is blind on purpose: you can drop things but cannot list it or read anyone's files. Do not open it by hand, use `Submit-Flag`.

## 4. How each activity is tracked

### A flag you submit

You find a `{FLAG}{...}` string and submit it with `Submit-Flag` or from the web. Flags are yours: submitting someone else's costs 10 points and is logged. Copy it whole, braces included and without spaces.

### A writeup in `H:\{DELIVER_DIR}`

No command is involved. The file just has to exist with the exact name: `day1-map`, `day2-writeup`, `day3-writeup` and so on up to `day7-writeup`. Any of these extensions works, and each format has its own minimum size:

| Format | Minimum |
|---|---|
| `.txt` `.md` | 500 bytes |
| `.excalidraw` | 800 bytes |
| `.rtf` `.html` | 1.5 KB |
| `.svg` | 2 KB |
| `.pdf` `.odt` | 8 KB |
| `.docx` | 9 KB |
| `.png` `.jpg` | 20 KB |

The minimums differ because they do not measure the same thing: 500 bytes of plain text are half a written page, while 500 bytes of `.docx` are an empty document. The byte signature is checked, not the extension: renaming a `.txt` to `.pdf` does not work.

### Work the server checks on its own

Nothing to submit here. The grader inspects AD and your folder. If you do it in another path or another OU, it does not count.

| Challenge | What is checked |
|---|---|
| D4-02 | In `H:\{WORK_DIR}\{K_DAY4}\{K_CH2}`: at least 3 folders with at least 3 files each |
| D4-OPT1 | In `H:\{WORK_DIR}\{K_DAY4}`: one valid CSV and one valid JSON |
| D7-G1 | A logon hours GPO linked to your OU, or `logonHours` on an account in your OU |
| D7-G2 | A GPO linked to your OU with process creation auditing or script block logging |
| D7-G3 | A locked wallpaper GPO linked to your OU **and** filtered to a group other than Authenticated Users |
| D7-CREA | A user in your OU that belongs to a group other than its primary group |

## 5. Two common stumbles

**Error 1219 when mounting a share with another account.** Windows does not allow two connections to the same server with different users. If `H:` is already mounted, use the DC IP instead of its name for the second connection, or unmount first with `net use * /delete`.

**The hosts file is not enough.** It resolves single names, but it does not publish the SRV records Windows needs to find the controller. Joining requires the lab DNS.
