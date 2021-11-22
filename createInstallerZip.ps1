Compress-Archive -LiteralPath Eula.txt, Sysmon.exe, smconfig.xml, NXLOG_CE_LICENSE, nxlog-ce-2.10.2150.msi, OpenEDR.msi -DestinationPath installer.zip -Force

$TARGETFILE="install.ps1"

if(test-path "$PSScriptRoot\installer.zip"){
    $FileHash = Get-FileHash -Path installer.zip
    Write-Host $FileHash.Hash

    (Get-Content -path $TARGETFILE -Raw) -match "OPENEDR_SHA256_HASH='(.*)'"
    $matches[1]
    ((Get-Content -path $TARGETFILE -Raw) -replace $matches[1],$FileHash.Hash) | Set-Content -Path $TARGETFILE
    
}
