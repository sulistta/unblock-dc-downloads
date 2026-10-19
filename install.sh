#!/usr/bin/env bash
set -Eeuo pipefail

repo='sulistta/unblock-dc-downloads'
manifest_url="https://raw.githubusercontent.com/${repo}/main/latest.json"
base_url="https://github.com/${repo}/releases/download"

fail() {
    printf 'Unblock DC: %s\n' "$1" >&2
    exit 1
}

[[ $(uname -s) == Linux ]] || fail 'este instalador atende Linux.'
[[ $(uname -m) == x86_64 ]] || fail 'a versão publicada requer Linux x86_64.'
(( EUID != 0 )) || fail 'execute como seu usuário normal, sem sudo no comando inteiro.'
command -v curl >/dev/null || fail 'curl é necessário para baixar o instalador.'
command -v grep >/dev/null || fail 'grep não está disponível.'
command -v awk >/dev/null || fail 'awk não está disponível.'

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*|*fedora*|*rhel*|*suse*|*arch*) ;;
    *) fail 'distribuição não reconhecida. Requer systemd, polkit, iproute2 e OpenVPN 2.6+.' ;;
esac

command -v systemctl >/dev/null || fail 'systemd é necessário; esta distribuição não oferece systemctl.'
[[ -r /proc/1/comm && $(</proc/1/comm) == systemd ]] ||
    fail 'o systemd precisa estar ativo como gerenciador do sistema.'

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/unblock-dc-install.XXXXXXXX")
staged=''
cleanup() {
    rm -rf -- "$tmpdir"
    [[ -z $staged ]] || rm -f -- "$staged"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

download() {
    local limit=33554432
    [[ $1 != "$manifest_url" ]] || limit=16384
    curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error \
        --retry 2 --connect-timeout 15 --max-time 120 --max-filesize "$limit" \
        --output "$2" "$1"
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
download "$manifest_url" "$manifest" || fail 'não foi possível obter a lista de versões.'
[[ $(wc -c <"$manifest") -le 16384 ]] || fail 'manifesto de distribuição excede o tamanho permitido.'
schema=$(json_value schema "$manifest") || fail 'manifesto inválido.'
version=$(json_value version "$manifest") || fail 'versão ausente no manifesto.'
[[ $schema == 1 ]] || fail 'versão de manifesto não suportada.'
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'versão inválida no manifesto.'

linux_section=$(sed -nE '/"linux_x86_64"[[:space:]]*:/,/^[[:space:]]*},?[[:space:]]*$/p' "$manifest")
[[ -n $linux_section ]] || fail 'não há pacote Linux x86_64 publicado.'
section_file="$tmpdir/linux.json"
printf '%s\n' "$linux_section" >"$section_file"
url=$(json_value url "$section_file") || fail 'URL Linux inválida no manifesto.'
expected_url="${base_url}/v${version}/unblock-2-linux-x86_64"
[[ $url == "$expected_url" ]] || fail 'URL Linux não corresponde à versão publicada.'
expected_hash=$(json_value sha256 "$section_file") || fail 'SHA-256 ausente no manifesto.'
[[ $expected_hash =~ ^[[:xdigit:]]{64}$ ]] || fail 'SHA-256 inválido no manifesto.'
expected_hash=${expected_hash,,}

binary="$tmpdir/unblock-2"
download "$url" "$binary" || fail 'não foi possível baixar o executável Linux.'
[[ -s $binary ]] || fail 'o executável baixado está vazio.'
(( $(wc -c <"$binary") <= 33554432 )) || fail 'o executável excede o tamanho permitido.'
if command -v sha256sum >/dev/null; then
    actual_hash=$(sha256sum "$binary" | awk '{print $1}')
elif command -v shasum >/dev/null; then
    actual_hash=$(shasum -a 256 "$binary" | awk '{print $1}')
else
    fail 'sha256sum ou shasum é necessário para verificar o download.'
fi
[[ $actual_hash == "$expected_hash" ]] || fail 'o SHA-256 do executável não confere; nenhum arquivo foi instalado.'

run_admin() {
    if command -v sudo >/dev/null; then
        sudo "$@"
    elif command -v pkexec >/dev/null; then
        pkexec "$@"
    else
        fail 'instale sudo ou pkexec para preparar as dependências do sistema.'
    fi
}

missing=0
for command_name in openvpn ip pkexec; do
    command -v "$command_name" >/dev/null || missing=1
done
if (( missing )); then
    case "${ID:-}" in
        ubuntu|debian)
            run_admin apt-get update
            run_admin apt-get install -y --no-install-recommends openvpn iproute2 policykit-1 ca-certificates
            ;;
        fedora)
            run_admin dnf install -y openvpn iproute polkit ca-certificates
            ;;
        rhel|redhat|centos|rocky|almalinux|ol)
            if command -v dnf >/dev/null; then
                run_admin dnf install -y epel-release || true
                run_admin dnf install -y openvpn iproute polkit ca-certificates
            else
                run_admin yum install -y epel-release || true
                run_admin yum install -y openvpn iproute polkit ca-certificates
            fi
            ;;
        opensuse*|sles)
            run_admin zypper --non-interactive refresh
            run_admin zypper --non-interactive install openvpn iproute2 polkit ca-certificates
            ;;
        arch|manjaro)
            run_admin pacman -S --needed --noconfirm openvpn iproute2 polkit ca-certificates
            ;;
        *) fail 'não sei instalar dependências automaticamente nesta distribuição.' ;;
    esac
fi

for command_name in openvpn ip pkexec; do
    command -v "$command_name" >/dev/null || fail "a dependência $command_name não foi instalada."
done
openvpn_output=$(openvpn --version 2>&1) || fail 'OpenVPN não iniciou corretamente.'
openvpn_version=$(printf '%s\n' "$openvpn_output" | sed -nE '1s/^OpenVPN ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
[[ $openvpn_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'não foi possível identificar a versão do OpenVPN.'
openvpn_major=${openvpn_version%%.*}
openvpn_minor=${openvpn_version#*.}
openvpn_minor=${openvpn_minor%%.*}
(( openvpn_major == 2 && openvpn_minor >= 6 )) ||
    fail "OpenVPN $openvpn_version detectado; esta versão requer OpenVPN 2.6 ou superior. Atualize-o e execute o comando novamente."

bin_dir="$HOME/.local/bin"
mkdir -p -- "$bin_dir" || fail 'não foi possível preparar ~/.local/bin.'
installed="$bin_dir/unblock-2"
staged=$(mktemp "$bin_dir/.unblock-2.XXXXXXXX") || fail 'não foi possível preparar a atualização.'
cp -- "$binary" "$staged"
chmod 0755 "$staged"
mv -f -- "$staged" "$installed"
staged=''

printf 'Instalando Unblock DC %s. Autorize a janela de autenticação do sistema.\n' "$version"
if ! "$installed" install; then
    fail 'a integração não foi instalada. O comando unblock-2 foi mantido em ~/.local/bin para reparo ou remoção.'
fi
printf '\nInstalação concluída. Abra o Discord; a conexão inicia automaticamente.\n'
printf 'Status: %s status\n' "$installed"
printf 'Remover: feche o Discord e execute %s remove\n' "$installed"
