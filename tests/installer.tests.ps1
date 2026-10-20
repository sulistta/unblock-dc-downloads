$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
. "$PSScriptRoot\..\install.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ('unblock-installer-check-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
$script:checks=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Expect-Failure([scriptblock]$Action,[string]$Pattern){
    $errorText=$null;try{& $Action}catch{$errorText=$_.Exception.Message}
    Check ($null -ne $errorText -and $errorText -match $Pattern) "Falha esperada ausente: $Pattern ($errorText)"
}
function Test-Case([string]$Name,[scriptblock]$Action){& $Action;$script:checks++;Write-Host "PASS $Name"}
New-Item -ItemType Directory -Path $root | Out-Null
try {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){Expect-Failure {Assert-UnblockPlatform} 'Windows'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $source=Join-Path $root 'source';New-Item -ItemType Directory $source | Out-Null
    foreach($name in (@('unblock-2.exe','LICENSE','README.md')+@(Get-UnblockRuntimeFiles|ForEach-Object{'runtime/'+$_}))){
        $path=Join-Path $source $name;New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null;[IO.File]::WriteAllText($path,'fixture-'+$name)
    }
    $script:zip=Join-Path $root 'fixture.zip'
    $z=[IO.Compression.ZipFile]::Open($script:zip,'Create')
    foreach($name in (@('unblock-2.exe','LICENSE','README.md')+@(Get-UnblockRuntimeFiles|ForEach-Object{'runtime/'+$_}))){
        $entry=$z.CreateEntry($name);$stream=$entry.Open();$bytes=[Text.Encoding]::UTF8.GetBytes('fixture-'+$name);$stream.Write($bytes,0,$bytes.Length);$stream.Dispose()
    };$z.Dispose()
    $script:hash=(Get-FileHash $script:zip -Algorithm SHA256).Hash
    function Reset-Fixture {
        $env:LOCALAPPDATA=Join-Path $root ([guid]::NewGuid().ToString('N'))
        $script:manifest=@{schema=2;version='0.7.0';windows_x64=@{url='https://github.com/sulistta/unblock-dc-downloads/releases/download/v0.7.0/unblock-2-windows-x64.zip';sha256=$script:hash}}
        $script:helperCalls=0;$script:signature='Valid';$script:helperFails=$false;$script:temporary=$null
    }
    function Assert-UnblockPlatform {}
    function Get-AuthenticodeSignature {param($LiteralPath);return @{Status=$script:signature}}
    function Start-Process {throw 'Unexpected external installer'}
    function Save-UnblockDownload([string]$Url,[string]$Destination){
        if($Url -like '*/latest.json'){$script:temporary=Split-Path $Destination;[IO.File]::WriteAllText($Destination,($script:manifest|ConvertTo-Json -Depth 5))}
        elseif($Url -like '*.zip'){Copy-Item $script:zip $Destination}
        else{throw 'Unexpected dependency download'}
    }
    function Invoke-UnblockHelper([string]$Executable){
        Check ([IO.File]::ReadAllText($Executable) -ceq 'fixture-unblock-2.exe') 'Executavel diferente do pacote validado.'
        foreach($name in Get-UnblockRuntimeFiles){Check (Test-Path -LiteralPath (Join-Path (Split-Path $Executable) ('runtime/'+$name))) 'Runtime incompleto no auxiliar.'}
        $script:helperCalls++;if($script:helperFails){throw 'fixture helper failure'}
    }
    Test-Case 'installs the complete verified payload without a separate installer' {
        Reset-Fixture;Install-UnblockDc
        Check ($script:helperCalls -eq 1) 'Auxiliar ausente.'
        Check (Test-Path (Join-Path $env:LOCALAPPDATA 'unblock-2/bin/runtime/openvpn.exe')) 'Runtime privado ausente.'
        Check (-not (Test-Path $script:temporary)) 'Downloads permaneceram.'
    }
    Test-Case 'updates the complete CLI and runtime and removes staging folders' {
        $bin=Join-Path $env:LOCALAPPDATA 'unblock-2/bin';[IO.File]::WriteAllText((Join-Path $bin 'unblock-2.exe'),'previous')
        Install-UnblockDc
        Check ([IO.File]::ReadAllText((Join-Path $bin 'unblock-2.exe')) -ceq 'fixture-unblock-2.exe') 'Atualizacao falhou.'
        Check (@(Get-ChildItem (Split-Path $bin) -Force|Where-Object Name -like '.*').Count -eq 0) 'Stage ou backup permaneceu.'
    }
    Test-Case 'corrupt downloads never reach the helper' {
        Reset-Fixture;$script:manifest.windows_x64.sha256='0'*64;Expect-Failure {Install-UnblockDc} 'verificacao'
        Check ($script:helperCalls -eq 0 -and -not (Test-Path $script:temporary)) 'Download invalido alterou a instalacao.'
    }
    Test-Case 'unsigned runtime does not change the existing installation' {
        Reset-Fixture;$bin=Join-Path $env:LOCALAPPDATA 'unblock-2/bin';New-Item -ItemType Directory $bin -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $bin 'unblock-2.exe'),'previous');$script:signature='NotSigned'
        Expect-Failure {Install-UnblockDc} 'assinatura'
        Check ($script:helperCalls -eq 0 -and [IO.File]::ReadAllText((Join-Path $bin 'unblock-2.exe')) -ceq 'previous') 'Runtime invalido alterou o CLI.'
    }
    Test-Case 'foreign URLs, old schemas, bad hashes and mismatched versions fail before installation' {
        foreach($url in @('http://github.com/package.zip','https://evil.example/package.zip','https://github.com/sulistta/unblock-dc-downloads/releases/download/v0.8.0/unblock-2-windows-x64.zip')){
            Reset-Fixture;$script:manifest.windows_x64.url=$url;Expect-Failure {Install-UnblockDc} 'Pacote'
        }
        Reset-Fixture;$script:manifest.schema=1;Expect-Failure {Install-UnblockDc} 'Versao'
        Reset-Fixture;$script:manifest.windows_x64.sha256='bad';Expect-Failure {Install-UnblockDc} 'Pacote'
    }
    Test-Case 'missing, duplicate and traversal entries are rejected before extraction' {
        foreach($kind in @('missing','duplicate','traversal')){
            $bad=Join-Path $root ($kind+'.zip');Copy-Item $script:zip $bad
            $z=[IO.Compression.ZipFile]::Open($bad,'Update')
            if($kind -eq 'missing'){$z.GetEntry('runtime/openvpn.exe').Delete()}
            elseif($kind -eq 'duplicate'){$null=$z.CreateEntry('runtime/openvpn.exe')}
            else{$null=$z.CreateEntry('../escaped.txt')};$z.Dispose()
            $destination=Join-Path $root ($kind+'-destination');New-Item -ItemType Directory $destination|Out-Null
            Expect-Failure {Expand-UnblockPackage $bad $destination} 'Pacote|Arquivo'
            Check (@(Get-ChildItem $destination).Count -eq 0) 'Pacote invalido extraiu arquivos.'
        }
    }
    Test-Case 'helper failure preserves the old installation and restores TLS' {
        Reset-Fixture;$bin=Join-Path $env:LOCALAPPDATA 'unblock-2/bin';New-Item -ItemType Directory $bin -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $bin 'unblock-2.exe'),'previous');$script:helperFails=$true;$tls=[Net.ServicePointManager]::SecurityProtocol
        Expect-Failure {Install-UnblockDc} 'fixture helper failure'
        Check ([IO.File]::ReadAllText((Join-Path $bin 'unblock-2.exe')) -ceq 'previous') 'Falha removeu o CLI anterior.'
        Check (-not (Test-Path $script:temporary) -and [Net.ServicePointManager]::SecurityProtocol -eq $tls) 'Limpeza ou TLS invalido.'
    }
    Write-Host "Installer: $script:checks checks passed. No real helper was executed."
}finally{$env:LOCALAPPDATA=$oldLocal;Remove-Item -LiteralPath $root -Recurse -Force}
