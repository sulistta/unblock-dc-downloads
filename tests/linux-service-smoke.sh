#!/usr/bin/env bash
# Exercise the protected runtime, real systemd IPC and cleanup without a provider account.
set -Eeuo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $EUID != 0 ]] || { echo 'Use a disposable GitHub Linux runner.' >&2; exit 1; }
helper=$(realpath "$1")
account=$(id -u)
fixture=$(mktemp -d)
export XDG_DATA_HOME="$fixture/data"
credential_dir="$XDG_DATA_HOME/unblock-2"
core="$fixture/discord_desktop_core-1/discord_desktop_core"
voice="$fixture/discord_voice-1/discord_voice"
mkdir -p "$core" "$voice" "$credential_dir"
chmod 0700 "$credential_dir"
printf '{"username":"FixtureUser","password":"FixturePassword"}' >"$credential_dir/proton-credentials.dat"
chmod 0600 "$credential_dir/proton-credentials.dat"
printf 'module.exports = {};' >"$core/index.js"
printf 'module.exports = {};' >"$voice/index.js"
touch "$core/core.asar" "$voice/discord_voice.node"
cleanup() {
    sudo env PKEXEC_UID="$account" "$helper" --remove-service "$account" || true
    "$helper" remove --discord-root "$fixture" || true
    rm -rf -- "$fixture"
}
trap cleanup EXIT
sudo env PKEXEC_UID="$account" "$helper" --setup-service "$account"
"$helper" install --discord-root "$fixture"
"$helper" install --discord-root "$fixture"
node - "$account" <<'JS'
const net=require('node:net'),assert=require('node:assert/strict');
const socket=net.connect('/run/unblock-2-'+process.argv[2]+'.sock');
const timer=setTimeout(()=>{socket.destroy();throw new Error('IPC timeout');},10000);
let output='';socket.on('connect',()=>socket.end('invalid-json\n'));
socket.on('data',bytes=>output+=bytes);socket.on('error',error=>{throw error;});
socket.on('close',()=>{clearTimeout(timer);assert.match(output,/helper-error/);});
JS
# Stop is synchronous: the service's complete cgroup must have exited.
sudo systemctl stop "unblock-2-$account.service"
if pgrep -f '^/usr/local/lib/unblock-2/runtime/openvpn ' >/dev/null; then echo 'VPN process leaked' >&2; exit 1; fi
if [[ -n $(ls /run/netns/unblock2-* 2>/dev/null || true) ]]; then echo 'Named namespace leaked' >&2; exit 1; fi
