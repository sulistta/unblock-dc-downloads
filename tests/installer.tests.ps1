param([string]$OpenVpnMsi)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. "$PSScriptRoot\..\install.ps1"
$script:realHash=(Get-Command Assert-UnblockHash).ScriptBlock
$script:root=Join-Path ([IO.Path]::GetTempPath()) ('unblock-installer-check-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
$script:checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Expect-Failure([scriptblock]$Action,[string]$Pattern){
    $errorText=$null
    try{& $Action}catch{$errorText=$_.Exception.Message}
    Check ($null -ne $errorText -and $errorText -match $Pattern) "Falha esperada ausente: $Pattern ($errorText)"
}
function Test-Case([string]$Name,[scriptblock]$Action){& $Action;$script:checks++;Write-Host "PASS $Name"}
New-Item -ItemType Directory -Path $script:root | Out-Null
try {
    # Read and parse the same dependency the installer uses, without installing
    # it. Windows also checks its real signature before the process is mocked.
    $msi=Join-Path $script:root 'official.msi'
    if($OpenVpnMsi){Copy-Item -LiteralPath $OpenVpnMsi -Destination $msi}
    else{Save-UnblockDownload 'https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.23-I002-amd64.msi' $msi}
    Assert-UnblockHash $msi '31809e97debe44c12be06ed892c2a43e55b67b31cb852827b7ec8f2d6c0b8dc6'
    if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){
        Check ((Get-AuthenticodeSignature -LiteralPath $msi).Status -eq 'Valid') 'Assinatura real do MSI invalida.'
        Assert-UnblockPlatform
    }else{Expect-Failure {Assert-UnblockPlatform} 'Windows'}
    $script:msi=$msi
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $source=Join-Path $script:root 'source';New-Item -ItemType Directory -Path $source | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'unblock-2.exe'),'MZ-test-application')
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'),'test-license')
    $script:zip=Join-Path $script:root 'fixture.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($source,$script:zip)
    $script:hash=(Get-FileHash $script:zip -Algorithm SHA256).Hash.ToLowerInvariant()
    function Reset-Fixture {
        $env:LOCALAPPDATA=Join-Path $script:root ([guid]::NewGuid().ToString('N'))
        $script:manifest=@{schema=1;version='0.6.0';windows_x64=@{url='https://github.com/sulistta/unblock-dc-downloads/releases/download/v0.6.0/unblock-2-windows-x64.zip';sha256=$script:hash}}
        $script:haveVpn=$true;$script:helperCalls=0;$script:msiCalls=0;$script:msiExit=0;$script:signature='Valid';$script:badMsi=$false;$script:helperFails=$false;$script:temporary=$null
    }
    function Assert-UnblockPlatform {}
    function Get-UnblockOpenVpn {if($script:haveVpn){return 'installed-openvpn'}}
    function Get-AuthenticodeSignature {param($LiteralPath) return @{Status=$script:signature}}
    function Start-Process {param($FilePath,$Verb,$ArgumentList,[switch]$Wait,[switch]$PassThru)
        Check ($Verb -eq 'RunAs' -and $Wait -and $PassThru) 'MSI sem elevacao ou espera.'
        Check ($ArgumentList -contains '/norestart' -and $ArgumentList -contains '/qn') 'MSI sem instalacao silenciosa/controlada.'
        $script:msiCalls++;$script:haveVpn=$true;return @{ExitCode=$script:msiExit}
    }
    function Save-UnblockDownload([string]$Url,[string]$Destination){
        if($Url -like '*/latest.json'){$script:temporary=Split-Path $Destination;[IO.File]::WriteAllText($Destination,($script:manifest|ConvertTo-Json -Depth 5));return}
        if($Url -like '*.msi'){
            Copy-Item $script:msi $Destination
            if($script:badMsi){[IO.File]::WriteAllText($Destination,'corrupt')}
        }else{Copy-Item $script:zip $Destination}
    }
    function Invoke-UnblockHelper([string]$Executable){
        Check ([IO.File]::ReadAllText($Executable) -eq 'MZ-test-application') 'Executavel diferente do pacote validado.'
        $script:helperCalls++;if($script:helperFails){throw 'fixture helper failure'}
    }
    Test-Case 'installs a verified package and keeps a usable CLI' {
        Reset-Fixture;Install-UnblockDc
        Check ($script:helperCalls -eq 1 -and $script:msiCalls -eq 0) 'Instalacao inesperada.'
        Check (Test-Path (Join-Path $env:LOCALAPPDATA 'unblock-2\bin\unblock-2.exe')) 'CLI nao foi preservada.'
        Check (-not (Test-Path $script:temporary)) 'Arquivos temporarios permaneceram.'
    }
    Test-Case 'updates atomically without deleting the previous file first' {
        $target=Join-Path $env:LOCALAPPDATA 'unblock-2\bin\unblock-2.exe';[IO.File]::WriteAllText($target,'previous')
        Install-UnblockDc;Check ([IO.File]::ReadAllText($target) -eq 'MZ-test-application') 'Atualizacao falhou.'
        Check (@(Get-ChildItem (Split-Path $target) -Filter '*.tmp').Count -eq 0) 'Arquivo de atualizacao permaneceu.'
    }
    Test-Case 'corrupt package is rejected before dependency/helper changes' {
        Reset-Fixture;$script:manifest.windows_x64.sha256='0'*64
        Expect-Failure {Install-UnblockDc} 'verificacao'
        Check ($script:helperCalls -eq 0 -and $script:msiCalls -eq 0 -and -not (Test-Path $script:temporary)) 'Download invalido alterou a instalacao.'
    }
    Test-Case 'foreign, insecure, mismatched-version URLs and malformed hashes are rejected' {
        foreach($url in @('http://github.com/sulistta/unblock-dc-downloads/releases/download/v0.6.0/unblock-2-windows-x64.zip','https://evil.example/package.zip','https://github.com/sulistta/unblock-dc-downloads/releases/download/v0.7.0/unblock-2-windows-x64.zip')){
            Reset-Fixture;$script:manifest.windows_x64.url=$url;Expect-Failure {Install-UnblockDc} 'Pacote'
        }
        Reset-Fixture;$script:manifest.windows_x64.sha256='bad';Expect-Failure {Install-UnblockDc} 'Pacote'
        Reset-Fixture;$script:manifest.version='../oops';Expect-Failure {Install-UnblockDc} 'Versao'
    }
    Test-Case 'missing executable and duplicate executable entries are rejected' {
        $empty=Join-Path $script:root 'empty.zip';$z=[IO.Compression.ZipFile]::Open($empty,'Create');$z.Dispose()
        Expect-Failure {Expand-UnblockPackage $empty $script:root} 'Executavel'
        $duplicate=Join-Path $script:root 'duplicate.zip';$z=[IO.Compression.ZipFile]::Open($duplicate,'Create')
        $null=$z.CreateEntry('unblock-2.exe');$null=$z.CreateEntry('unblock-2.exe');$z.Dispose()
        Expect-Failure {Expand-UnblockPackage $duplicate $script:root} 'Executavel'
    }
    Test-Case 'only the exact executable entry is extracted' {
        $traversal=Join-Path $script:root 'traversal.zip';Copy-Item $script:zip $traversal
        $z=[IO.Compression.ZipFile]::Open($traversal,'Update');$null=$z.CreateEntry('../escaped.txt');$z.Dispose()
        $dest=Join-Path $script:root 'extraction';New-Item -ItemType Directory $dest | Out-Null
        $null=Expand-UnblockPackage $traversal $dest
        Check (@(Get-ChildItem $dest).Count -eq 1 -and -not (Test-Path (Join-Path $script:root 'escaped.txt'))) 'Extracao saiu do destino.'
    }
    Test-Case 'missing dependency downloads and validates the actual official MSI before elevation' {
        Reset-Fixture;$script:haveVpn=$false;Install-UnblockDc
        Check ($script:msiCalls -eq 1 -and $script:helperCalls -eq 1) 'Dependencia nao foi instalada antes da integracao.'
    }
    Test-Case 'corrupt or unsigned MSI never starts an elevated process' {
        Reset-Fixture;$script:haveVpn=$false;$script:badMsi=$true;Expect-Failure {Install-UnblockDc} 'verificacao'
        Check ($script:msiCalls -eq 0 -and $script:helperCalls -eq 0) 'MSI corrompido executado.'
        Reset-Fixture;$script:haveVpn=$false;$script:signature='NotSigned';Expect-Failure {Install-UnblockDc} 'assinatura'
        Check ($script:msiCalls -eq 0 -and $script:helperCalls -eq 0) 'MSI sem assinatura executado.'
    }
    Test-Case 'reboot requests and MSI errors do not claim integration success' {
        foreach($code in @(3010,1603)){Reset-Fixture;$script:haveVpn=$false;$script:msiExit=$code;Expect-Failure {Install-UnblockDc} 'reinicializacao|nao foi concluida';Check ($script:helperCalls -eq 0) 'Integracao executada apos falha/reboot.'}
    }
    Test-Case 'helper failure preserves the CLI for repair but cleans downloads' {
        Reset-Fixture;$script:helperFails=$true;$oldTls=[Net.ServicePointManager]::SecurityProtocol
        Expect-Failure {Install-UnblockDc} 'fixture helper failure'
        Check (-not (Test-Path $script:temporary) -and [Net.ServicePointManager]::SecurityProtocol -eq $oldTls) 'Falha deixou arquivos ou alterou TLS.'
    }
    Write-Host "Installer: $script:checks checks passed. No real helper or MSI was executed."
} finally {
    $env:LOCALAPPDATA=$oldLocal
    Remove-Item -LiteralPath $script:root -Recurse -Force
}
