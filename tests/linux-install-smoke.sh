#!/usr/bin/env bash
# Full public command on a disposable runner, with pre-authorized system setup.
set -Eeuo pipefail
[[ ${GITHUB_ACTIONS:-} == true && $EUID != 0 ]] || exit 1
fixture=$(mktemp -d)
export XDG_CONFIG_HOME="$fixture/config"
export XDG_DATA_HOME="$fixture/data"
account=$(id -u)
core="$XDG_CONFIG_HOME/discord/0.0.0/modules/discord_desktop_core-1/discord_desktop_core"
voice="$XDG_CONFIG_HOME/discord/0.0.0/modules/discord_voice-1/discord_voice"
mkdir -p "$core" "$voice" "$fixture/package"
printf 'module.exports = {};' >"$core/index.js"
printf 'module.exports = {};' >"$voice/index.js"
touch "$core/core.asar" "$voice/discord_voice.node"
curl -fsSL https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/latest.json -o "$fixture/latest.json"
curl -fsSL "$(jq -r '.linux_x86_64.url' "$fixture/latest.json")" -o "$fixture/package.tar.gz"
tar -xzf "$fixture/package.tar.gz" -C "$fixture/package"
helper="$fixture/package/unblock-2"
cleanup() {
    if [[ -e /etc/systemd/system/unblock-2-$account.socket ]]; then sudo env PKEXEC_UID="$account" "$helper" --remove-service "$account" || true; fi
    if [[ -x $HOME/.local/bin/unblock-2 ]]; then "$HOME/.local/bin/unblock-2" remove || true; fi
    rm -rf -- "$fixture"
}
trap cleanup EXIT
# CI has no desktop authorization agent. The same protected setup is explicitly
# authorized with sudo first; the user installer then detects that exact payload.
sudo env PKEXEC_UID="$account" "$helper" --setup-service "$account"
baseline=$(command -v openvpn || true)
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.sh | bash'
[[ $("$HOME/.local/bin/unblock-2" status | jq -r '.integrated') -ge 1 ]]
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.sh | bash'
[[ $(command -v openvpn || true) == "$baseline" ]]
cleanup
trap - EXIT
[[ ! -e /etc/systemd/system/unblock-2-$account.socket && ! -e /usr/local/lib/unblock-2 ]]
printf 'Linux: published command, update and removal passed.\n'
