#!/usr/bin/env bash
# Exercise the protected runtime, real systemd IPC, HTTPS/UDP and cleanup on CI.
set -Eeuo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $EUID != 0 ]] || { echo 'Use a disposable GitHub Linux runner.' >&2; exit 1; }
helper=$(realpath "$1")
network=$(realpath "$2")
account=$(id -u)
fixture=$(mktemp -d)
core="$fixture/discord_desktop_core-1/discord_desktop_core"
voice="$fixture/discord_voice-1/discord_voice"
mkdir -p "$core" "$voice"
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
"$network"
# Stop is synchronous: the service's complete cgroup must have exited.
sudo systemctl stop "unblock-2-$account.service"
if pgrep -f '^/usr/local/lib/unblock-2/runtime/openvpn ' >/dev/null; then echo 'VPN process leaked' >&2; exit 1; fi
if [[ -n $(ls /run/netns/unblock2-* 2>/dev/null || true) ]]; then echo 'Named namespace leaked' >&2; exit 1; fi
