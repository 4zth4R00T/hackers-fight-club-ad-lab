# {LAB}: student guide

Welcome to **{ORG}**. For seven days you will move through a real Windows company: its domain, its users, its file shares and its policies. Scattered around are flags in the `{FLAG}{...}` format.

Flags are **yours**: they are derived from your account, so your classmate's flag differs from yours. If you submit one that is not yours, the scoreboard notices, it scores nothing and it is logged.

## Before you start

| You need | Why |
|---|---|
| Windows 10 or 11 Pro, Enterprise or Education | The Home edition cannot join a domain |
| Access to the lab network | It may be Tailscale, a VPN, the VMware network or the local network: your instructor will tell you |
| Your user name and password | Your instructor hands them out |

Everything is done with a single script, `Join-Lab.ps1`, available in `\\{DC}\{SHARE_PUBLIC}\Scripts` together with `lab.json`. Copy both to a folder on your computer and run it **in PowerShell as administrator**.

First check that you can reach the lab. This changes nothing: it walks the whole chain and tells you which link is broken.

```powershell
.\Join-Lab.ps1
```

If it comes out clean, prepare and join the computer:

```powershell
.\Join-Lab.ps1 -Join -User first.last
```

Restart, sign in as `{NETBIOS}\first.last` and wait a minute. You will have:

| What | Where |
|---|---|
| Your lab for days 2 to 5 | `%USERPROFILE%\{KIT_DIR}` |
| Your network drive | `H:` |
| Your deliverables | `H:\{DELIVER_DIR}` |
| Your mailbox | `H:\{MAIL_DIR}\Inbox` |
| Course material | `\\{DC}\{SHARE_PUBLIC}` |

## The commands you will use

```powershell
Submit-Flag "{FLAG}{...}"      # submit a flag
Get-Progress                   # see how you are doing
Get-Progress -Detail           # challenge by challenge
Get-Challenges 2 -Hints        # one day of challenges with its public hint
Get-Hint D2-03                 # the next hint for a challenge, at no cost
```

Hints tell you where to look, not how. The path and the command are up to you: that is the exercise.

The class scoreboard lives at **{WEB_URL}**. You can also submit flags there with your domain user and password, even from a computer that is not joined.

The grader runs every minute. After submitting, wait a moment before checking.

### You also have mail

{ORG} gave you a mailbox: `first.last@{DOMAIN}`. It is a real server.

```powershell
Get-LabMail                    # your inbox
Read-LabMail 1                 # read a message
Send-LabMail -To someone@{DOMAIN} -Subject "Question" -Body "..."
```

You sign in with your domain user and password. If you prefer a mail client, the server is `{MAIL_HOST}`, SMTP on 25 or 587 and POP3 on 110. The most instructive way is by hand with `telnet {MAIL_HOST} 25`: you will see authentication, the envelope and the message as separate layers.

## Scoring

| Item | Points |
|---|---|
| Each challenge | Its own value, from 10 to 40 |
| First blood | 5 extra for whoever solves it first |
| Full day | 25 extra after finishing every mandatory challenge of the day |
| Submitting someone else's flag | Costs 10 and is logged |

There are 36 challenges: 620 mandatory points and 100 optional ones.

Not every challenge is submitted. Challenge 2 of day 4 and the four administration tasks of day 7 are checked by the grader directly. Writeups go into `H:\{DELIVER_DIR}` named after the day, for example `day2-writeup.md`. Templates are in `\\{DC}\{SHARE_PUBLIC}\{TEMPLATES_DIR}`.

## The map of the seven days

**Day 1. Getting to know Windows.** Draw your mind map: what Windows is, the desktop environment, files and consoles. What matters is that the pieces are connected.

**Day 2. The command prompt.** Five flags on your own computer, all within reach of CMD, in places that exist on every Windows box and that almost nobody checks.

**Day 3. Windows under the hood.** The registry, NTFS alternate streams and links: three corners where Windows lets you hide things.

**Day 4. Automating.** No hunting by hand here: you write the program that hunts for you.

**Day 5. The network.** Three chained parts: what you get from one is the key to the next. There are also two optional ones: a DC port that fits no table and the company mail server.

**Day 6. Active Directory.** An AD object has about thirty fields and normal queries show you only a few. The flags live exactly in the hidden ones.

**Day 7. Administer.** You switch chairs. You get your own OU inside `OU={OU_SANDBOX}` where you are in charge: create your GPOs and users there. And write the machine writeup with its defense section.

## Rules

**Your plot is your OU.** It carries your slot name, not your user name. You can see it with `(Get-Item H:).Target`. Working in the wrong OU is the most common way to lose the day 7 points.

**Do not touch the domain controller.** If you break it, you break it for the whole class.

**Nothing you learn here gets tried elsewhere.** Not at home, not on the school network, not just to see. Offensive knowledge is only ethical with explicit written authorization.

**The lab has integrity controls**, and you are told so up front because that is fair. Take notes as you work: copying commands as you use them takes ten seconds; rebuilding them from memory days later takes an hour.

## When something fails

| Symptom | What to do |
|---|---|
| `{KIT_DIR}` does not show up | Sign out and back in. The log is at `C:\ProgramData\Lab\deploy.log` |
| `Submit-Flag` cannot reach the server | `Test-NetConnection {DCFQDN} -Port 445` and check your connection to the lab network |
| `Submit-Flag` is not recognized | Open a new PowerShell window or run `Import-Module Student` |
| I submitted a flag and it does not score | Copy it whole, braces included and without spaces. And make sure it is yours |

Developed by Aztharot. Instagram: @its_aztharot.exe. GitHub: github.com/4zth4R00T.
