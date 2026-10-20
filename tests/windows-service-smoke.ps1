param([Parameter(Mandatory=$true)][string]$Helper, [string]$NetworkExecutable)
# Run in an elevated PowerShell with Discord closed. A fake Discord tree and
# a disposable service exercise the real installer. Always clean in finally.
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Execute em um PowerShell como administrador.' }
$sid = $identity.User.Value
$name = "unblock-2-$sid"
if (Get-Service -Name $name -ErrorAction SilentlyContinue) { throw 'Use um usuario de teste sem a integracao instalada.' }
$Helper = (Resolve-Path $Helper).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$oldLocal = $env:LOCALAPPDATA
$oldChannel = $env:UNBLOCK_TEST_CHANNEL
$oldTestData = $env:UNBLOCK_TEST_DATA
$env:LOCALAPPDATA = Join-Path $fixture 'profile'
$root = Join-Path $fixture 'Discord\app-1.0.0\modules\discord_desktop_core-1\discord_desktop_core'
$voice = Join-Path $fixture 'Discord\app-1.0.0\modules\discord_voice-1\discord_voice'
New-Item -ItemType Directory -Force -Path $root,$voice,$env:LOCALAPPDATA | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'index.js'), 'module.exports = {};')
[IO.File]::WriteAllText((Join-Path $root 'core.asar'), '')
[IO.File]::WriteAllText((Join-Path $voice 'index.js'), 'module.exports = {};')
[IO.File]::WriteAllText((Join-Path $voice 'discord_voice.node'), '')
function Run-Helper([string]$action) {
    & $Helper $action --discord-root (Join-Path $fixture 'Discord')
    if ($LASTEXITCODE -ne 0) { throw "Auxiliar falhou: $action" }
}
function Connect-Channel {
    $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', "unblock-2-$sid", [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $pipe.Connect(5000)
    return $pipe
}
function Wait-Clean {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $workers = @(Get-CimInstance Win32_Process -Filter "Name = 'unblock-2.exe'" | Where-Object { $_.CommandLine -like "*--windows-worker $sid *" })
        $sessions = @(Get-ChildItem -LiteralPath "$env:ProgramData\unblock-2\$sid" -Directory -Filter 'session-*' -ErrorAction SilentlyContinue)
        $adapters = @(Get-NetAdapter -IncludeHidden -Name "UnblockDC-$sid" -ErrorAction SilentlyContinue)
        if ($workers.Count -eq 0 -and $sessions.Count -eq 0 -and $adapters.Count -eq 0) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'A sessao anterior reteve processos ou credenciais.'
}
try {
    Run-Helper 'install'
    Run-Helper 'install'
    $manifest = Get-Content "$env:LOCALAPPDATA\unblock-2\installation.json" -Raw | ConvertFrom-Json
    $runtime = Get-Content (Join-Path $manifest.runtime 'runtime.json') -Raw | ConvertFrom-Json
    $env:UNBLOCK_TEST_CHANNEL = "\\.\pipe\unblock-2-$sid"
    $env:UNBLOCK_TEST_DATA = Join-Path $env:LOCALAPPDATA 'network-check'
    if ($runtime.helperChannel -ne $env:UNBLOCK_TEST_CHANNEL) { throw 'Canal instalado incorreto.' }
    if ((Get-Service $name).Status -ne 'Running') { throw 'Servico nao iniciou.' }
    foreach ($privatePath in @("$env:ProgramFiles\unblock-2\$sid", "$env:ProgramData\unblock-2\$sid")) {
        $acl = Get-Acl -LiteralPath $privatePath
        if (-not $acl.AreAccessRulesProtected) { throw 'ACL herdada no diretorio privado.' }
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544') { throw 'Proprietario incorreto no diretorio privado.' }
        $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        if ($rules.Count -ne 2) { throw 'Permissoes adicionais no diretorio privado.' }
        foreach ($rule in $rules) {
            if ($rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') -or $rule.AccessControlType -ne 'Allow' -or $rule.FileSystemRights -ne 'FullControl') { throw 'Permissao indevida no diretorio privado.' }
        }
    }
    $pipe = Connect-Channel
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes("invalid-json`n")
        $pipe.Write($bytes,0,$bytes.Length)
        $reader = [IO.StreamReader]::new($pipe)
        $reply = $reader.ReadLineAsync()
        if (-not $reply.Wait(10000) -or $reply.Result -notmatch 'helper-error') { throw 'Pedido invalido nao foi recusado.' }
    } finally { $pipe.Dispose() }
    Wait-Clean
    $pipe = Connect-Channel
    $bytes = [Text.Encoding]::UTF8.GetBytes('{"ca":')
    $pipe.Write($bytes,0,$bytes.Length)
    $pipe.Dispose()
    Wait-Clean
    $pipe = Connect-Channel
    try {
        Stop-Service $name
        (Get-Service $name).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(15))
    } finally { $pipe.Dispose() }
    Start-Service $name
    (Get-Service $name).WaitForStatus('Running',[TimeSpan]::FromSeconds(15))
    Wait-Clean
    $broker = Get-CimInstance Win32_Service -Filter "Name='$name'"
    if (@(Get-NetTCPConnection -OwningProcess $broker.ProcessId -ErrorAction SilentlyContinue).Count -ne 0 -or @(Get-NetUDPEndpoint -OwningProcess $broker.ProcessId -ErrorAction SilentlyContinue).Count -ne 0) { throw 'O broker ocioso abriu uma porta de rede.' }
    if ($NetworkExecutable) {
        & $NetworkExecutable
        if ($LASTEXITCODE -ne 0) { throw 'Falha na verificacao de rede.' }
        Wait-Clean
    }
    Run-Helper 'remove'
    if (Get-Service $name -ErrorAction SilentlyContinue) { throw 'O servico permaneceu instalado.' }
    if ((Get-Content (Join-Path $root 'index.js') -Raw) -ne 'module.exports = {};') { throw 'A remocao nao restaurou o modulo.' }
    Write-Host 'Windows: instalacao, atualizacao, IPC, cancelamento, parada e limpeza verificados.'
} finally {
    try { if (Get-Service $name -ErrorAction SilentlyContinue) { Run-Helper 'remove' } } catch { Write-Warning $_.Exception.Message }
    $env:LOCALAPPDATA = $oldLocal
    $env:UNBLOCK_TEST_CHANNEL = $oldChannel
    $env:UNBLOCK_TEST_DATA = $oldTestData
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
