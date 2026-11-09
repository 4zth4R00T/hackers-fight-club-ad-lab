# How to submit and check your progress

```powershell
Submit-Flag "{FLAG}{...}"      # submit a flag
Get-Progress                   # your score
Get-Progress -Detail           # challenge by challenge
Get-Challenges 2 -Hints        # when you get stuck
Get-Hint D2-03                 # tiered hint, costs nothing
```

The grader runs every minute. Class scoreboard: **{WEB_URL}**. From the web you can also submit flags and upload your writeup as `.txt`, `.md`, `.pdf`, `.docx` or `.excalidraw`.

## Not everything is submitted

Some challenges are checked automatically: challenge 2 of day 4 and the four administration tasks of day 7. There is no flag there, only work to do, and the grader looks at your `H:` drive and your OU.

## Writeups score

They go into `H:\{DELIVER_DIR}` named after the day: `day1-map.md`, `day2-writeup.md` and so on up to `day7-writeup.md`. There is one template per day in `\\{DC}\{SHARE_PUBLIC}\{TEMPLATES_DIR}`. A two line file does not count: real content is expected.

## Your mail

```powershell
Get-LabMail
Read-LabMail 1
Send-LabMail -To someone@{DOMAIN} -Subject "..." -Body "..."
```

Server `{MAIL_HOST}`, SMTP 25 or 587 and POP3 110, with your domain user.

## Rules

Your plot is your OU inside `OU={OU_SANDBOX}`. Outside of it you are a regular user. Do not touch the domain controller. Nothing you learn here is tried elsewhere without explicit written authorization.
