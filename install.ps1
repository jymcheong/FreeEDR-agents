function Test-Administrator  
{  
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}

if(!(Test-Administrator))
{
    Write-Error "This script must be executed as Administrator.";
    exit;
}

if ($PSVersionTable.PSVersion.Major -lt 5)
{
    Write-Error "Need Powershell 5 or above.";
    exit;
}

$TARGETDIR="c:\windows\openedr"
$DOWNLOADDIR="$env:TEMP\openedr"
$INSTALLERZIP='installer.zip'
$OPENEDRFILENAME='openedr.msi'
$NXLOGFILENAME="nxlog-ce-2.10.2150.msi"
$NET46FILENAME="NDP46-KB3045557-x86-x64-AllOS-ENU.exe"

$openEdrInstallerURL='https://github.com/jymcheong/openedrClient/blob/master/installer.zip?raw=true'
$net46InstallerURL='https://download.microsoft.com/download/C/3/A/C3A5200B-D33C-47E9-9D70-2F7C65DAAD94/NDP46-KB3045557-x86-x64-AllOS-ENU.exe'

# System.Net.WebClient will fail to download if remote site has TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$OPENEDR_SHA256_HASH='87CDBAB6DDE3D1659EC3BE8109289DFB3443684572E0E9639EBFDB0AE60DDD4E'
$NET46_SHA256_HASH='B21D33135E67E3486B154B11F7961D8E1CFD7A603267FB60FEBB4A6FEAB5CF87'

# clear any previously downloaded installer.zip
if(Test-Path "C:\$INSTALLERZIP") { Remove-Item -LiteralPath "C:\$INSTALLERZIP" -Force -Recurse | Out-Null }

# Create a location to download the files to
if(Test-Path $DOWNLOADDIR) { Remove-Item -LiteralPath $DOWNLOADDIR -Force -Recurse | Out-Null }
New-Item -ItemType Directory -Force -Path $DOWNLOADDIR | Out-Null

$wc = New-Object System.Net.WebClient

# Check .NET 4.6
$net46 = $false
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -recurse |
Get-ItemProperty -name Version,Release -EA 0 | ForEach-Object { if($_.Release -ge 393295) { $net46 = $true}}
if($net46 -eq $false) {
    $wc.DownloadFile("https://raw.githubusercontent.com/jymcheong/openedrClient/master/install.ps1", "$DOWNLOADDIR\install.ps1")
    Set-Location -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    Set-ItemProperty -Path . -Name installOpenEDR -Value "C:\WINDOWS\system32\WindowsPowerShell\v1.0\powershell.exe -noexit  -executionPolicy Unrestricted -File $DOWNLOADDIR\install.ps1"
    Write-Output "Downloading .NET 4.6 Standalone Installer..."
    $wc.DownloadFile($net46InstallerURL, "$DOWNLOADDIR\$NET46FILENAME")
    $FileHash = Get-FileHash -Path "$DOWNLOADDIR\$NET46FILENAME"
    if($FileHash.Hash -ne $NET46_SHA256_HASH) { Write-Host 'Checksum failed!'; exit } 
    Write-Output "Installing .NET 4.6..."
    Start-Process -FilePath "$env:comspec" -Verb runAs -Wait -ArgumentList "/c $DOWNLOADDIR\$NET46FILENAME"
    shutdown /r /t 30
    exit
}

if(!(Test-Path "$PSScriptRoot\installer.zip")){
   # Download the installers...
   Write-Host 'Downloading OpenEDR...'
   $wc.DownloadFile($openEdrInstallerURL, "$PSScriptRoot\$INSTALLERZIP")
}

$FileHash = Get-FileHash -Path "$PSScriptRoot\$INSTALLERZIP"
if($FileHash.Hash -ne $OPENEDR_SHA256_HASH) { Write-Host 'Checksum failed!'; exit } 

Write-Host "Extracting OpenEDR installers..."
[System.Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
[System.IO.Compression.ZipFile]::ExtractToDirectory("$PSScriptRoot\$INSTALLERZIP",$DOWNLOADDIR)

# uninstall if existing target directory exists
if(Test-Path $TARGETDIR) {
    Invoke-Expression $wc.DownloadString('https://raw.githubusercontent.com/jymcheong/openedrClient/master/uninstall.ps1')
}

# start the installations
Set-Location $DOWNLOADDIR
Write-Output "Installing OpenEDR..."
Start-Process -FilePath "$env:comspec" -Verb runAs -Wait -ArgumentList "/c msiexec /i $OPENEDRFILENAME TARGETDIR=$TARGETDIR /qb /L*V OPENEDRinstall.log"

Write-Output "Installing Sysmon..."
Start-Process -FilePath "$env:comspec" -Verb runAs -Wait -ArgumentList "/c sysmon.exe -accepteula -i $DOWNLOADDIR\smconfig.xml"

if(!$standAlone) { # see https://github.com/jymcheong/OpenEDRclient/issues/12
    Write-Output "Installing NXLOG-CE..."
    Start-Process -FilePath "$env:comspec" -Verb runAs -Wait -ArgumentList "/c msiexec /i $NXLOGFILENAME INSTALLDIR=$TARGETDIR\nxlog /qb /L*V NXLOGinstall.log"
}

## Deploy in detectOnly mode; NO automated termination of foreign-file-backed processes
if($detectOnly) {
  New-Item -ItemType Directory -Force -Path "$TARGETDIR\conf\dfpm\detectOnly" | Out-Null 
}

if($capturePEfiles) {
  New-Item -ItemType Directory -Force -Path "$TARGETDIR\conf\dfpm\UploadSample" | Out-Null 
}


## Office Macro Configurations
$officePath = (Get-ItemProperty  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Winword.exe" -ErrorAction SilentlyContinue).Path 
if($officePath -match 'Office(?<officeVersion>\d\d)')
{
    if(!$allowMacro){
        Write-Host "Found office version!"
        $version = $Matches.officeVersion + ".0"
        if([int]$version -lt 15) {
            $regName = "VBAWarnings"
            $regValue = 2
        }
        else {
            $regName = "blockcontentexecutionfrominternet"
            $regValue = 1
        }

        # for Word 
        if(!$allowWordMacro) {
            # test with HKLM but doesn't work...
            $regWordPath = "HKCU:\SOFTWARE\Microsoft\office\" + $version + "\Word\security"
            if(!(Test-Path $regWordPath)) {
                New-Item -Path $regWordPath -Force
            }
            New-ItemProperty -Path $regWordPath -Name $regName -Value $regValue -Force
        }

        # for Excel 
        if(!$allowExcelMacro) {
            $regExcelPath = "HKCU:\SOFTWARE\Microsoft\office\" + $version + "\Excel\security"
            if(!(Test-Path $regExcelPath)) { 
               New-Item -Path $regExcelPath -Force
            }
            New-ItemProperty -Path $regExcelPath -Name $regName -Value $regValue -Force
         }

         # for PowerPoint 
        if(!$allowPowerPointMacro) {
            $regPowerPointPath = "HKCU:\SOFTWARE\Microsoft\office\" + $version + "\PowerPoint\security"
            if(!(Test-Path $regPowerPointPath)) {
               New-Item -Path $regPowerPointPath -Force
            }
            New-ItemProperty -Path $regPowerPointPath -Name $regName -Value $regValue -Force
         }
   }
} 

# Download configuration 
## Download the SFTP upload-destination configuration if defined
if($SFTPCONFURL) {
    $wc.DownloadFile($SFTPCONFURL, "$TARGETDIR\sftpconf.zip")    
}

## Update the target directory within various scheduled-task configuration files
Set-Location "$TARGETDIR\installers"
((Get-Content -path DFPM.xml -Raw) -replace 'TARGETDIR',$TARGETDIR) | Set-Content -Path DFPM.xml
((Get-Content -path UploadSchtasks.xml -Raw) -replace 'TARGETDIR',$TARGETDIR) | Set-Content -Path UploadSchtasks.xml
((Get-Content -path uatSchedTask.xml -Raw) -replace 'UATPATH',"$TARGETDIR\uat.exe") | Set-Content -Path uatSchedTask.xml
((Get-Content -path uatSchedTask.xml -Raw) -replace 'TARGETDIR',"$TARGETDIR") | Set-Content -Path uatSchedTask.xml
((Get-Content -path nxlog.conf -Raw) -replace 'TARGETDIR',"$TARGETDIR\") | Set-Content -Path "$TARGETDIR\nxlog\conf\nxlog.conf"

schtasks /Create /TN "DFPM" /XML "DFPM.xml"

if(!$standAlone) {
    schtasks /Create /TN "UAT" /XML "uatSchedTask.xml"
    schtasks /Create /TN "UATupload" /XML "UploadSchtasks.xml"
}

# Turn on Powershell ScriptBlockLogging
New-Item -Path "HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging" -Value 1 -Force

# Deny HTA execution, see https://github.com/jymcheong/OpenEDRclient/issues/2
cmd /c ftype HTAFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype VBSFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype VBEFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype JSFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype JSEFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype WSFFile=C:\Windows\System32\notepad.exe %1
cmd /c ftype WSHFile=C:\Windows\System32\notepad.exe %1

# Start agents
if(!$standAlone) { schtasks /Run /TN "UATupload" }
schtasks /Run /TN "DFPM"

# Start log rotation
$scpath = $env:WinDir + "\system32\sc.exe"
if(!$standAlone) {
    Start-Process -FilePath $scpath -Verb runAs -Wait -ArgumentList "start nxlog"
    Write-Output "Started Nxlog service!"
}
else{ # otherwise network address events will fill up the directory because there is no uploading & clean-up
    Start-Process -FilePath $scpath -Verb runAs -Wait -ArgumentList "stop datafusion"
    Write-Output "Stopped DataFusion service!"
}

# Notify user
Add-Type -AssemblyName System.Windows.Forms
$global:balmsg = New-Object System.Windows.Forms.NotifyIcon
$path = (Get-Process -id $pid).Path
$balmsg.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
$balmsg.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
$balmsg.BalloonTipText = 'OpenEDR installation completed! System will reboot in 5 mins!'
$balmsg.BalloonTipTitle = "Attention $Env:USERNAME"
$balmsg.Visible = $true
$balmsg.ShowBalloonTip(20000)

shutdown /r /t 300

# Windows 10 Attack Surface Reduction Rules
if (Get-Command "Set-MpPreference" -errorAction SilentlyContinue)
{   
    # Block executable content from email client and webmail
    Set-MpPreference -AttackSurfaceReductionRules_Ids BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue
    
    # Block all Office applications from creating child processes
    Set-MpPreference -AttackSurfaceReductionRules_Ids D4F940AB-401B-4EFC-AADC-AD5F3C50688A -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue
    
    # Block Office applications from injecting code into other processes
    Set-MpPreference -AttackSurfaceReductionRules_Ids 75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block Office applications from injecting code into other processes
    Set-MpPreference -AttackSurfaceReductionRules_Ids 75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block execution of potentially obfuscated scripts
    Set-MpPreference -AttackSurfaceReductionRules_Ids 5BEB7EFE-FD9A-4556-801D-275E5FFC04CC -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block Win32 API calls from Office macros
    Set-MpPreference -AttackSurfaceReductionRules_Ids 92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block credential stealing from the Windows local security authority subsystem (lsass.exe)
    Set-MpPreference -AttackSurfaceReductionRules_Ids 9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block process creations originating from PSExec and WMI commands
    Set-MpPreference -AttackSurfaceReductionRules_Ids d1e49aac-8f56-4280-b9ba-993a6d77406c -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block untrusted and unsigned processes that run from USB
    Set-MpPreference -AttackSurfaceReductionRules_Ids b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block Office communication application from creating child processes
    Set-MpPreference -AttackSurfaceReductionRules_Ids 26190899-1602-49e8-8b27-eb1d0a1ce869 -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block Adobe Reader from creating child processes
    Set-MpPreference -AttackSurfaceReductionRules_Ids 7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

    # Block persistence through WMI event subscription
    Set-MpPreference -AttackSurfaceReductionRules_Ids e6db77e5-3df2-4cf1-b95a-636979351e5b -AttackSurfaceReductionRules_Actions Enabled -errorAction SilentlyContinue

} 

# Enable 4688, 4689 & commandLine audit events
reg add HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit\ /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1

auditpol.exe /set /subcategory:"Process Creation" /success:enable /failure:enable

auditpol.exe /set /subcategory:"Process Termination" /success:enable /failure:enable








































