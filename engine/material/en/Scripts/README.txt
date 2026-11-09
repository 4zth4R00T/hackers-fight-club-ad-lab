Copy Join-Lab.ps1 and lab.json to a folder on your computer and run,
in PowerShell as administrator:

    .\Join-Lab.ps1                          checks without changing anything
    .\Join-Lab.ps1 -Join -User first.last   prepares and joins the computer

lab.json holds the domain, the DC address and the network mode of the
lab. It contains no passwords.
