# Unblock DC - Windows x64. This is the public installer, not the application source.
function Assert-UnblockPlatform {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSVersion.Major -lt 5) {
        throw 'Use o PowerShell 5.1 ou superior no Windows.'
    }
    $architecture = $env:PROCESSOR_ARCHITEW6432
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }
    if ($architecture -ne 'AMD64' -or -not [Environment]::Is64BitProcess) {
        throw 'Use o PowerShell de 64 bits em um Windows x64.'
    }
    $session = (Get-Process -Id $PID).SessionId
    $discord = @(Get-Process -Name Discord,DiscordPTB,DiscordCanary -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
    if ($discord.Count) { throw 'Feche completamente o Discord, incluindo a bandeja, e execute o comando novamente.' }
}
function Save-UnblockDownload([string]$Url, [string]$Destination) {
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 120 -Headers @{'User-Agent'='UnblockDC-Installer'} | Out-Null
}
function Assert-UnblockHash([string]$File, [string]$Expected) {
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$' -or (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Expected) {
        throw 'A verificacao do download falhou. Nenhum arquivo baixado sera executado.'
    }
}
function Get-UnblockOpenVpn {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        $bin = Join-Path $base 'OpenVPN\bin'
        $exe = Join-Path $bin 'openvpn.exe'
        if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath (Join-Path $bin 'tapctl.exe')) -and (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Wintun')) {
            $text = (& $exe --version 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $text -match '^OpenVPN (\d+\.\d+\.\d+)' -and [version]$Matches[1] -ge [version]'2.6.23') { return $exe }
        }
    }
}
function Install-UnblockOpenVpn([string]$Directory) {
    if (Get-UnblockOpenVpn) { return }
    Write-Host 'Instalando OpenVPN/Wintun pelo instalador oficial...'
    $msi = Join-Path $Directory 'OpenVPN.msi'
    Save-UnblockDownload 'https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.23-I002-amd64.msi' $msi
    Assert-UnblockHash $msi '31809e97debe44c12be06ed892c2a43e55b67b31cb852827b7ec8f2d6c0b8dc6'
    $signature = Get-AuthenticodeSignature -LiteralPath $msi
    if ($signature.Status -ne 'Valid') { throw 'O Windows nao confirmou a assinatura do instalador OpenVPN.' }
    $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -Verb RunAs -ArgumentList @('/i',('"'+$msi+'"'),'/qn','/norestart') -Wait -PassThru
    if ($process.ExitCode -eq 3010) { throw 'O Windows solicitou uma reinicializacao. Reinicie e execute este comando novamente.' }
    if ($process.ExitCode -ne 0 -or -not (Get-UnblockOpenVpn)) { throw 'A instalacao do OpenVPN/Wintun nao foi concluida.' }
}
function Get-UnblockRelease([string]$Directory) {
    $manifest = Join-Path $Directory 'latest.json'
    Save-UnblockDownload 'https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/latest.json' $manifest
    if ((Get-Item -LiteralPath $manifest).Length -gt 16384) { throw 'Manifesto de distribuicao invalido.' }
    $release = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($release.schema -ne 1 -or $release.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Versao de distribuicao invalida.' }
    $expected = 'https://github.com/sulistta/unblock-dc-downloads/releases/download/v'+$release.version+'/unblock-2-windows-x64.zip'
    if ($release.windows_x64.url -cne $expected -or $release.windows_x64.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Pacote de distribuicao invalido.' }
    return $release
}
function Expand-UnblockPackage([string]$Archive, [string]$Directory) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $entries = @($zip.Entries | Where-Object FullName -ceq 'unblock-2.exe')
        if ($entries.Count -ne 1 -or $entries[0].Length -lt 2 -or $entries[0].Length -gt 33554432) { throw 'Executavel ausente ou invalido no pacote.' }
        $destination = Join-Path $Directory 'unblock-2.exe'
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], $destination, $false)
        return $destination
    } finally { $zip.Dispose() }
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
    $tls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $tls -bor [Net.SecurityProtocolType]::Tls12
        New-Item -ItemType Directory -Path $directory | Out-Null
        $release = Get-UnblockRelease $directory
        Write-Host ('Baixando Unblock DC '+$release.version+'...')
        $archive = Join-Path $directory 'package.zip'
        Save-UnblockDownload $release.windows_x64.url $archive
        Assert-UnblockHash $archive $release.windows_x64.sha256
        $executable = Expand-UnblockPackage $archive $directory
        Install-UnblockOpenVpn $directory
        # Keep a verified CLI in the account profile for status/removal. Never
        # delete the previous CLI before its atomic replacement is ready.
        $bin = Join-Path $env:LOCALAPPDATA 'unblock-2\bin'
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        $target = Join-Path $bin 'unblock-2.exe'
        $staged = Join-Path $bin ([guid]::NewGuid().ToString('N')+'.tmp')
        try {
            Copy-Item -LiteralPath $executable -Destination $staged
            if (Test-Path -LiteralPath $target) { [IO.File]::Replace($staged, $target, [System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($staged, $target) }
        } finally { if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Force } }
        Invoke-UnblockHelper $target
        Write-Host 'Instalacao concluida. Abra o Discord; a conexao sera automatica.'
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $tls
        if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    }
}
# Dot-sourcing exposes the functions for the installer checks without running it.
if ($MyInvocation.InvocationName -ne '.') { Install-UnblockDc }
