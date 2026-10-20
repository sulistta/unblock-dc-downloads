# Unblock DC

Instaladores e executáveis oficiais para Windows x64 e Linux x86_64. O código da aplicação é mantido em um repositório privado.

## Linux

Feche completamente o Discord e execute como seu usuário normal:

```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.sh | bash'
```

O pacote inclui OpenVPN estático e verifica SHA-256 antes de instalar. Não instala OpenVPN ou iproute2 pelo gerenciador de pacotes. Autorize a janela do desktop uma vez. Requer kernel 5.3+, TUN nativo, systemd, polkit/pkexec, curl e tar. Desktop oficial do Discord; Flatpak, Snap, WSL e outras arquiteturas não são atendidos por este pacote.

```sh
~/.local/bin/unblock-2 status
# Encerre completamente o Discord antes de remover:
~/.local/bin/unblock-2 remove
```

## Windows

Feche completamente o Discord, incluindo a bandeja. No PowerShell de 64 bits, como seu usuário normal:

```powershell
irm https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.ps1 | iex
```

O pacote inclui OpenVPN e suas bibliotecas em uma pasta privada. O instalador verifica SHA-256 e as assinaturas dos componentes oficiais. Autorize a janela UAC para registrar o auxiliar e o driver DCO assinado. O aplicativo OpenVPN, sua interface e seus serviços não são instalados. Se o Windows solicitar reinicialização, reinicie e repita o comando.

Requer Windows 10 versão 2004+ ou Windows 11 x64, PowerShell 5.1+ e Discord desktop oficial. Windows ARM64, navegador e Microsoft Store não são atendidos por este pacote.

```powershell
& "$env:LOCALAPPDATA\unblock-2\bin\unblock-2.exe" status
# Encerre completamente o Discord antes de remover:
& "$env:LOCALAPPDATA\unblock-2\bin\unblock-2.exe" remove
```

Abra o Discord e use os controles nativos para assistir e transmitir. A conexão é automática; a voz comum continua direta. Não é necessário criar conta VPN ou importar configurações. Para atualizar, feche o Discord e execute novamente o comando do seu sistema.

A remoção desabilita a integração, retira o auxiliar e seus adaptadores. No Linux, a última conta removida também apaga o runtime protegido. O Windows gerencia o pacote do driver no Driver Store. O CLI no perfil do usuário permanece disponível para status, reparo ou uma nova instalação.

## Downloads e componentes

Os pacotes completos, checksums e fontes correspondentes dos componentes de terceiros estão em [Releases](https://github.com/sulistta/unblock-dc-downloads/releases/latest). Para instalar manualmente, extraia o pacote completo mantendo a pasta `runtime` ao lado de `unblock-2` e execute `install`. As licenças ficam em `runtime/licenses`.

A disponibilidade das saídas RiseupVPN depende de terceiros. A integração escolhe a saída com uma sondagem atual e tenta recuperar quedas; não garante estabilidade prolongada. Testes de HTTPS e UDP não comprovam reprodução de uma live. A validação de mídia dentro do Discord no Windows ainda precisa de uma conta conectada. Atualizações do Discord podem substituir módulos integrados; nesse caso, execute novamente o instalador.
