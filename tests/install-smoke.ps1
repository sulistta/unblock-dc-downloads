# Destructive only to its own fake Discord tree on a fresh GitHub Windows runner.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if($env:GITHUB_ACTIONS -ne 'true'){throw 'Execute somente em um runner Windows descartavel do GitHub Actions.'}
$root=Join-Path $env:LOCALAPPDATA 'Discord'
$data=Join-Path $env:LOCALAPPDATA 'unblock-2'
if((Test-Path $root) -or (Test-Path $data)){throw 'O perfil de teste deve estar vazio.'}
$core=Join-Path $root 'app-1.0.0\modules\discord_desktop_core-1\discord_desktop_core'
$voice=Join-Path $root 'app-1.0.0\modules\discord_voice-1\discord_voice'
$cli=Join-Path $data 'bin\unblock-2.exe'
$original='module.exports = {};'
# Pin the public installer to this run's commit: main can advance while a run
# is queued, and GitHub's branch URL can still serve the previous cached file.
$installerUrl='https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/'+$env:GITHUB_SHA+'/install.ps1'
try {
    New-Item -ItemType Directory -Path $core,$voice -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $core 'index.js'),$original)
    [IO.File]::WriteAllText((Join-Path $core 'core.asar'),'')
    [IO.File]::WriteAllText((Join-Path $voice 'index.js'),$original)
    [IO.File]::WriteAllText((Join-Path $voice 'discord_voice.node'),'')
    # Exercise exactly the published one-command entry point, then update.
    $installer=Invoke-RestMethod $installerUrl
    $checkedOut=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\install.ps1'))
    if(($installer -replace "`r`n","`n") -cne ($checkedOut -replace "`r`n","`n")){throw 'O instalador publicado nao corresponde a este teste.'}
    Invoke-Expression $installer
    if(-not (Test-Path $cli)){throw 'CLI ausente apos instalacao.'}
    $status=& $cli status | ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $status.integrated -lt 1 -or [IO.File]::ReadAllText((Join-Path $voice 'index.js')) -notmatch 'BEGIN UNBLOCK-2 INTEGRATION'){throw 'Os modulos do Discord nao foram integrados.'}
    . "$PSScriptRoot\..\install.ps1"
    if(-not (Get-UnblockOpenVpn)){
        Write-Host ('Wintun service: '+(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Wintun'))
        foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)})){
            if(-not $base){continue};$exe=Join-Path $base 'OpenVPN\bin\openvpn.exe'
            Write-Host ($exe+': '+(Test-Path $exe))
            if(Test-Path $exe){$lines=@(& $exe --version 2>&1);Write-Host ($lines[0]+'; exit='+$LASTEXITCODE)}
        }
        throw 'OpenVPN/Wintun nao esta disponivel apos instalacao.'
    }
    Invoke-Expression (Invoke-RestMethod $installerUrl)
    & $cli remove
    if($LASTEXITCODE -ne 0){throw 'A remocao falhou.'}
    if([IO.File]::ReadAllText((Join-Path $core 'index.js')) -ne $original){throw 'A remocao nao restaurou o modulo.'}
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if(Get-Service "unblock-2-$sid" -ErrorAction SilentlyContinue){throw 'O servico permaneceu instalado.'}
    Write-Host 'Windows: comando publico instalou dependencias, integrou, atualizou e removeu corretamente.'
} finally {
    if(Test-Path $cli){& $cli remove}
    Remove-Item $root,$data -Recurse -Force -ErrorAction SilentlyContinue
}
