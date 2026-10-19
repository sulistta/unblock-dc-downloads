# Unblock DC

Instalador e downloads oficiais. Este repositorio distribui o instalador e os executaveis; o codigo da aplicacao e mantido separadamente.

## Linux x86_64

Feche completamente o Discord e execute no terminal:

```sh
bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.sh | bash'
```

O instalador verifica o SHA-256 do executavel, prepara OpenVPN 2.6+, iproute2 e polkit pelo gerenciador do sistema, e registra o auxiliar com systemd. Autorize a instalacao no terminal ou na janela do sistema. O comando fica em `~/.local/bin/unblock-2` para consultar o status e remover a integracao.

Requisitos: Linux x86_64, kernel 5.3 ou superior com pidfd, systemd ativo, polkit e Discord desktop oficial. A instalacao automatica atende Debian/Ubuntu, Fedora, RHEL e derivados, openSUSE e Arch/Manjaro. Flatpak, Snap, WSL sem systemd e outras arquiteturas nao fazem parte desta distribuicao.

```sh
~/.local/bin/unblock-2 status
# Encerre completamente o Discord antes de remover:
~/.local/bin/unblock-2 remove
```

OpenVPN permanece instalado como dependencia do sistema depois da remocao; o comando `unblock-2` tambem fica disponivel para futuras atualizacoes ou remocoes.

## Windows x64

Encerre completamente o Discord, incluindo o icone na bandeja. Abra o **PowerShell de 64 bits** como seu usuario normal e execute:

```powershell
irm https://raw.githubusercontent.com/sulistta/unblock-dc-downloads/main/install.ps1 | iex
```

O comando baixa a versao publicada, confere seu SHA256, instala OpenVPN/Wintun quando necessario e aplica a integracao. Autorize as janelas de administrador do Windows quando aparecerem. Se o instalador de driver solicitar reinicializacao, reinicie o computador e execute o mesmo comando novamente.

Abra o Discord e use os controles nativos para assistir ou transmitir. A conexao e automatica; a voz comum continua direta. Nao e necessario compilar, criar conta VPN ou importar configuracoes. Para atualizar, feche o Discord e execute o mesmo comando.

### Status e remocao

```powershell
& "$env:LOCALAPPDATA\unblock-2\bin\unblock-2.exe" status
# Encerre completamente o Discord antes de remover:
& "$env:LOCALAPPDATA\unblock-2\bin\unblock-2.exe" remove
```

A remocao desabilita a integracao e o auxiliar. O OpenVPN e um programa separado e pode ser removido pelos aplicativos instalados do Windows, se nao for usado por outro software.

### Downloads manuais

Os executaveis e seus checksums estao em [Releases](https://github.com/sulistta/unblock-dc-downloads/releases/latest). O instalador usa HTTPS e valida o SHA256 do pacote. O MSI do OpenVPN tambem tem sua assinatura Authenticode conferida pelo Windows.

Requisitos: Windows 10 ou 11 x64, PowerShell 5.1 ou superior e Discord desktop oficial. Windows ARM64, navegador, Microsoft Store e clientes modificados nao fazem parte desta distribuicao. Atualizacoes do Discord podem substituir os modulos integrados; nesse caso, execute novamente o instalador.

A disponibilidade das saidas RiseupVPN depende de um servico de terceiros. Os testes nativos de rede e recuperacao passaram no Windows 11; reproducao e transmissao dentro do Discord no Windows ainda aguardam validacao com conta conectada. Nenhum resultado de HTTPS ou UDP e tratado como prova de reproducao de uma live.
