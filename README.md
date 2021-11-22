# Open Endpoint Defense & Response

* Tested on Windows 10, Server 2012R2 to 2019
* Protects endpoints from non-escalated file-based PE Malware (EXE/DLL) & Office-macro malware
* Detects Living-Off-The-Land offensive techniques without hard-coded rules
* Responds by automated or backend triggered malicious process termination 

It leverages the following components & reports to [an OpenEDR server (click to find out more)](https://github.com/jymcheong/OpenEDR).

## Sysmon
Sysinternal's license: https://docs.microsoft.com/en-us/sysinternals/license-terms

For non-Internet facing endpoints, please download Sysmon, modifiy `install.ps1` accordingly & host within your internal web-server.

## Nxlog-CE 
This is an archived version of NXLog-CE tested with OpenEDR client agents. For commercial deployments, please contact NXLOG for commercial license. 

## Building your own installer
- git clone this
- change Sysmon, smconfig.xml or whatever that you need to
- navigate to the project path (with cmd or powershell)
- run batch file: updateInstaller.bat

## Change-Log
See https://github.com/jymcheong/OpenEDRclient/commits/master
