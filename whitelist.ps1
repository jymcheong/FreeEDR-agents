param(
  [string]$FileName
)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
$result = [System.Windows.Forms.MessageBox]::Show('Are you sure?' , "Whitelist $Filename" , 'YesNo', 'Warning')
if ($result -eq 'No') {
    exit
}

Start-Process powershell.exe -WindowStyle hidden -verb runas -ArgumentList "-nologo -noninteractive -WindowStyle hidden -command get-acl C:\Windows\write.exe | Set-Acl $Filename"

[System.Windows.Forms.MessageBox]::Show("$Filename whitelisted!" , "Whitelisting Completed" , 'Ok', 'Info')