# Unblock DC - private, bundled network runtime. Run as the normal account.
function Assert-UnblockPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -lt 5) { throw 'Use o PowerShell 5.1 ou superior no Windows.' }
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ne 'AMD64' -or -not [Environment]::Is64BitProcess) { throw 'Use o PowerShell de 64 bits em um Windows x64.' }
    $session = (Get-Process -Id $PID).SessionId
    if (@(Get-Process -Name Discord,DiscordPTB,DiscordCanary -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session).Count) { throw 'Feche completamente o Discord, incluindo a bandeja, e execute o comando novamente.' }
}
function Save-UnblockDownload([string]$Url, [string]$Destination) {
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 180 -Headers @{'User-Agent'='UnblockDC-Installer'} | Out-Null
}
function Assert-UnblockHash([string]$File, [string]$Expected) {
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Expected) { throw 'A verificacao do download falhou. Nenhum arquivo baixado sera executado.' }
}
function Get-UnblockRuntimeFiles {
    @('openvpn.exe','tapctl.exe','libcrypto-3-x64.dll','libssl-3-x64.dll','libpkcs11-helper-1.dll','vcruntime140.dll',
      'drivers/nx20/ovpn-dco.inf','drivers/nx20/ovpn-dco.cat','drivers/nx20/ovpn-dco.sys',
      'drivers/nx21/ovpn-dco.inf','drivers/nx21/ovpn-dco.cat','drivers/nx21/ovpn-dco.sys',
      'licenses/NOTICE.txt','licenses/OpenVPN.txt','licenses/OpenSSL.txt','licenses/ThirdParty.txt')
}
function Get-UnblockRelease([string]$Directory) {
    $manifest = Join-Path $Directory 'latest.json'
    Save-UnblockDownload 'https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/latest.json' $manifest
    if ((Get-Item -LiteralPath $manifest).Length -gt 16384) { throw 'Manifesto de distribuicao invalido.' }
    $release = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($release.schema -ne 2 -or $release.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Versao de distribuicao invalida.' }
    $expected = 'https://github.com/sulistta/unblock-dc-downloads/releases/download/v'+$release.version+'/unblock-2-windows-x64.zip'
    if ($release.windows_x64.url -cne $expected -or $release.windows_x64.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Pacote de distribuicao invalido.' }
    return $release
}
function Expand-UnblockPackage([string]$Archive, [string]$Directory) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ((Get-Item -LiteralPath $Archive).Length -gt 67108864) { throw 'Pacote muito grande.' }
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $expected = @('unblock-2.exe','README.md','LICENSE') + @(Get-UnblockRuntimeFiles | ForEach-Object {'runtime/'+$_})
        if ($zip.Entries.Count -ne $expected.Count) { throw 'Pacote incompleto ou com arquivos inesperados.' }
        foreach ($name in $expected) {
            $entries = @($zip.Entries | Where-Object FullName -ceq $name)
            if ($entries.Count -ne 1 -or $entries[0].Length -lt 1 -or $entries[0].Length -gt 33554432 -or (($entries[0].ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Arquivo ausente, repetido ou invalido no pacote.' }
        }
        foreach ($entry in $zip.Entries) {
            $destination = Join-Path $Directory $entry.FullName
            New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
        }
        return (Join-Path $Directory 'unblock-2.exe')
    } finally { $zip.Dispose() }
}
function Assert-UnblockRuntime([string]$Directory) {
    foreach ($name in Get-UnblockRuntimeFiles) {
        if ($name -match '\.(exe|dll|cat)$') {
            if ((Get-AuthenticodeSignature -LiteralPath (Join-Path $Directory $name)).Status -ne 'Valid') { throw ('O Windows nao confirmou a assinatura do componente '+$name+'.') }
        }
    }
}
function Invoke-UnblockHelper([string]$Executable) {
    & $Executable install
    if ($LASTEXITCODE -ne 0) { throw 'A integracao nao foi instalada. Verifique a mensagem acima e tente novamente.' }
}
function Install-UnblockDc {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    Set-StrictMode -Version 2
    Assert-UnblockPlatform
    if (-not $env:LOCALAPPDATA) { throw 'O perfil do Windows nao esta disponivel.' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('unblock-dc-install-'+[guid]::NewGuid().ToString('N'))
    $base = Join-Path $env:LOCALAPPDATA 'unblock-2'
    $staged = Join-Path $base ('.bin-'+[guid]::NewGuid().ToString('N'))
    $backup = Join-Path $base ('.previous-'+[guid]::NewGuid().ToString('N'))
    $bin = Join-Path $base 'bin'
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Path $directory | Out-Null
        $release = Get-UnblockRelease $directory
        Write-Host ('Baixando Unblock DC '+$release.version+'...')
        $archive = Join-Path $directory 'package.zip'
        Save-UnblockDownload $release.windows_x64.url $archive
        Assert-UnblockHash $archive $release.windows_x64.sha256
        $null = Expand-UnblockPackage $archive $directory
        Assert-UnblockRuntime (Join-Path $directory 'runtime')
        New-Item -ItemType Directory -Force -Path $staged | Out-Null
        Copy-Item -LiteralPath (Join-Path $directory 'unblock-2.exe') -Destination $staged
        Copy-Item -LiteralPath (Join-Path $directory 'runtime') -Destination $staged -Recurse
        Invoke-UnblockHelper (Join-Path $staged 'unblock-2.exe')
        if (Test-Path -LiteralPath $bin) { [IO.Directory]::Move($bin, $backup) }
        try { [IO.Directory]::Move($staged, $bin) }
        catch { if (Test-Path -LiteralPath $backup) { [IO.Directory]::Move($backup, $bin) }; throw }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        Write-Host 'Instalacao concluida. Abra o Discord; a conexao sera automatica.'
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $tls
        foreach ($path in @($directory,$staged)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force } }
    }
}
if ($MyInvocation.InvocationName -ne '.') { Install-UnblockDc }
