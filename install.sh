#!/usr/bin/env bash
set -Eeuo pipefail
repo='sulistta/unblock-dc-downloads'
manifest_url="https://raw.githubusercontent.com/${repo}/main/latest.json"
fail() { printf 'Unblock DC: %s\n' "$1" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail 'este pacote requer Linux x86_64.'
(( EUID != 0 )) || fail 'execute como seu usuário normal, sem sudo no comando inteiro.'
for tool in curl tar awk sed grep sort mktemp; do command -v "$tool" >/dev/null || fail "$tool não está disponível."; done
command -v systemctl >/dev/null && [[ -r /proc/1/comm && $(</proc/1/comm) == systemd ]] || fail 'é necessário um desktop Linux com systemd ativo.'
command -v pkexec >/dev/null || fail 'o componente de autorização do desktop (polkit/pkexec) não está disponível.'
[[ -c /dev/net/tun ]] || fail 'o kernel precisa oferecer o dispositivo nativo /dev/net/tun.'
command -v sha256sum >/dev/null || fail 'sha256sum não está disponível.'
tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/unblock-dc-install.XXXXXXXX")
package=''
keep_package=0
staged_link=''
cleanup() {
    rm -rf -- "$tmpdir"
    [[ -z $package || $keep_package == 1 ]] || rm -rf -- "$package"
    [[ -z $staged_link ]] || rm -f -- "$staged_link"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP
download() {
    local limit=67108864
    [[ $1 != "$manifest_url" ]] || limit=16384
    curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --retry 2 --connect-timeout 15 --max-time 180 --max-filesize "$limit" --output "$2" "$1"
}
json_value() {
    local key=$1 file=$2 count value
    count=$(grep -cE "^[[:space:]]*\"${key}\"[[:space:]]*:" "$file" || true)
    [[ $count == 1 ]] || return 1
    value=$(awk -v key="\"${key}\":" '$1 == key { value=$2; sub(/,$/, "", value); sub(/^"/, "", value); sub(/"$/, "", value); print value }' "$file")
    [[ -n $value ]] || return 1
    printf '%s' "$value"
}
manifest="$tmpdir/latest.json"
download "$manifest_url" "$manifest" || fail 'não foi possível obter a versão publicada.'
[[ $(wc -c <"$manifest") -le 16384 ]] || fail 'manifesto muito grande.'
schema=$(json_value schema "$manifest") || fail 'manifesto inválido.'
version=$(json_value version "$manifest") || fail 'versão ausente.'
[[ $schema == 2 && $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'manifesto de pacote não suportado.'
sed -nE '/"linux_x86_64"[[:space:]]*:/,/^[[:space:]]*},?[[:space:]]*$/p' "$manifest" >"$tmpdir/linux.json"
url=$(json_value url "$tmpdir/linux.json") || fail 'URL Linux ausente.'
hash=$(json_value sha256 "$tmpdir/linux.json") || fail 'SHA-256 ausente.'
[[ $url == "https://github.com/${repo}/releases/download/v${version}/unblock-2-linux-x86_64.tar.gz" && $hash =~ ^[[:xdigit:]]{64}$ ]] || fail 'pacote Linux inválido no manifesto.'
archive="$tmpdir/package.tar.gz"
download "$url" "$archive" || fail 'não foi possível baixar o pacote Linux.'
[[ $(sha256sum "$archive" | awk '{print $1}') == "${hash,,}" ]] || fail 'o SHA-256 não confere; nenhum arquivo foi instalado.'
expected=(unblock-2 runtime/openvpn runtime/licenses/NOTICE.txt runtime/licenses/OpenVPN.txt runtime/licenses/OpenSSL.txt runtime/licenses/libcap-ng.txt README.md LICENSE)
actual=$(tar -tzf "$archive") || fail 'pacote corrompido.'
[[ $(printf '%s\n' "$actual" | LC_ALL=C sort) == "$(printf '%s\n' "${expected[@]}" | LC_ALL=C sort)" ]] || fail 'o pacote contém arquivos ausentes, repetidos ou inesperados.'
tar -tvzf "$archive" | awk 'substr($1,1,1)!="-" || $3>33554432 || $3<1 { invalid=1 } END { exit invalid }' || fail 'o pacote contém links ou arquivos inválidos.'
packages="$HOME/.local/share/unblock-2/packages"
bin="$HOME/.local/bin"
mkdir -p -- "$packages" "$bin"
package=$(mktemp -d "$packages/$version.XXXXXXXX")
tar -xzf "$archive" --directory "$package" --no-same-owner --no-same-permissions
chmod 0755 "$package/unblock-2" "$package/runtime/openvpn"
staged_link=$(mktemp "$bin/.unblock-2.XXXXXXXX")
rm -- "$staged_link"
ln -s -- "$package/unblock-2" "$staged_link"
mv -Tf -- "$staged_link" "$bin/unblock-2"
staged_link=''
keep_package=1
printf 'Instalando Unblock DC %s. Autorize a janela do sistema.\n' "$version"
"$bin/unblock-2" install || fail 'a integração não foi concluída. Execute o mesmo comando para tentar novamente.'
for previous in "$packages"/*; do
    [[ $previous != "$package" && -d $previous && ! -L $previous && ${previous##*/} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[A-Za-z0-9]{8}$ ]] || continue
    rm -rf -- "$previous"
done
printf '\nInstalação concluída. Abra o Discord; a conexão será automática.\n'
printf 'Status: %s/.local/bin/unblock-2 status\nRemover: %s/.local/bin/unblock-2 remove\n' "$HOME" "$HOME"
