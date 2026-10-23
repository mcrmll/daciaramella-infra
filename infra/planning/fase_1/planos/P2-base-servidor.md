# P2 — Base mínima do servidor (`base.yml`, versão 1)

Estado: feito a 23/10 · Depende de: P1 · Bloqueia: P3, P5, P6 · Executa: agente, com autorização do dono para correr contra o servidor · Máquinas: Mac mini → servidor

## Objetivo

O servidor passa a ter o que precisa para **correr** a app, e nada para a construir (D2). O que foi feito à mão a 10 e 16/10 fica escrito no Ansible, sem mudar nada no servidor.

## O que o `base.yml` v1 faz

**Novo:**

- **Docker e Compose** a partir dos repositórios do Ubuntu, como pede o plano geral: `docker.io` e `docker-compose-v2`. Antes de escrever a tarefa, confirmar os nomes dos pacotes no 26.04 (`apt-cache policy`). Não se instala nada de build.
- **`/etc/docker/daemon.json` com limite nos logs:** `log-driver: json-file`, `max-size: 10m` e `max-file: 3`. É a alteração 7 do plano geral.
- **Fuso Europe/Lisbon.** A verificação da janela de manutenção (P7) e os logs passam a estar na hora da loja.
- **Pastas:**
  - `/opt/daciaramella/` (root, 0750), com `anterior/` e `caddy/`;
  - `/opt/daciaramella/releases/`, onde os ficheiros de imagem chegam e de onde se apagam logo depois do `docker load`. Fica vazia entre deploys.
- **O `mciaramella` não entra no grupo `docker`.** Entrar no grupo equivale a ser root sem password. O Ansible usa o `sudo`.
- **O pacote `sudo`, o sudo clássico (`/usr/bin/sudo.ws`), fica garantido como instalado.**
  - O Ansible usa-o no `become` (`ansible_become_exe: sudo.ws`, no P1), porque com o `sudo-rs` dá timeout.
  - Se alguém o desinstalasse, o `become` deixava de funcionar sem se perceber porquê.
  - O `sudo` por omissão do sistema continua a ser o `sudo-rs`.

**Já feito à mão; passa a estar escrito e não deve mudar nada:**

- `/etc/ssh/sshd_config.d/10-hardening.conf`
- `/etc/cloud/cloud-init.disabled`
- Regras do `ufw`: negar tudo o que entra, menos 22/tcp a partir de `10.77.0.0/24`.
- **Netplan: nesta versão só se verifica**, com `assert` sobre o conteúdo de `/etc/netplan/01-loja.yaml`. Não se escreve. Um erro no netplan corta o acesso ao servidor.

**Fica de fora:** chrony, espelho do apt, MOTD, `snapd`, `open-vm-tools`, `smartd`, nftables e proxy ([ESTADO](../ESTADO.md), "Fora desta fase"). O Tailscale fica para depois desta fase (D13).

## Passos

1. **(agente) Ler, sem mudar nada, o conteúdo atual** do `10-hardening.conf`, do `01-loja.yaml` e do `ufw status verbose`. Os modelos têm de ficar iguais ao que lá está.
2. **(agente) Escrever o `playbooks/base.yml`.** Tem uma tarefa por ponto acima e um handler para reiniciar o Docker quando o `daemon.json` mudar.
3. **(agente, com o dono) `ansible-playbook playbooks/base.yml --check --diff`.** Só pode mostrar alterações no que é novo: Docker, `daemon.json`, fuso e pastas. Se aparecer alguma diferença no SSH, no `ufw` ou no cloud-init, parar e corrigir o modelo.
4. **(agente, com autorização) Correr a sério**, com uma sessão SSH aberta em paralelo, para o caso de alguma coisa trancar o acesso.
5. **(agente) Correr outra vez:** tem de dar `changed=0`.

## Registo

**19/10, passo 1 (só leituras, autorizado pelo dono):**
- **SSH:** o `10-hardening.conf` (root, 0644) tem as linhas `PasswordAuthentication no`, `PermitRootLogin no` e `KbdInteractiveAuthentication no`.
  - O `50-cloud-init.conf` (0600) continua lá, com `PasswordAuthentication yes`, e perde para o `10-`. O `sshd -T` confirma `passwordauthentication no`.
  - O `base.yml` não lhe mexe.
- **cloud-init:** o `cloud-init.disabled` (0644) tem o texto que o instalador do Ubuntu lá pôs, e o modelo copia-o igual.
- **ufw:**
  - ativo, com registo `low`;
  - nega o que entra e deixa sair tudo; o encaminhamento (*routed*) está desligado;
  - uma só regra: `22/tcp ALLOW IN 10.77.0.0/24`, com o comentário `SSH rede loja`;
  - `IPV6=yes`.
- **Netplan:** o `01-loja.yaml` (0600) tem DHCP na `eno1`, com `match` pelo MAC `10:e7:c6:05:90:2a` e `dhcp6: false`.
- **Fuso:** `Etc/UTC`, com o NTP ativo. Não há `/etc/docker`, e o `/opt` está vazio.
- **Pacotes no 26.04:**
  - os candidatos são `docker.io` 29.1.3 e `docker-compose-v2` 2.40.3;
  - o sudo clássico (`sudo` 1.9.17p2) já está instalado, e o `python3-apt` também;
  - o `docker.io` recomenda o `git`, o `pigz`, o `ubuntu-fan`, o `xz-utils`, o `apparmor` e o `ca-certificates`. Instala-se **sem as recomendações** (`install_recommends: false`), porque o servidor não constrói nada.

**19/10, passo 2:** escrito o `playbooks/base.yml`, com 15 tarefas e 2 handlers (recarregar o SSH, reiniciar o Docker). O `--syntax-check` passou.

**23/10, passo 3 (`--check --diff`, autorizado pelo dono):**
- **As tarefas já feitas à mão deram todas `ok`:** SSH, cloud-init, as quatro do `ufw`, o netplan e o sudo.
- **As novas deram `changed`:** o fuso, o `/etc/docker`, o `daemon.json`, os pacotes (`docker.io`, `docker-compose-v2`, `containerd` e `runc`, sem o `pigz` e o `ubuntu-fan`) e as pastas.
- **A primeira corrida falhou na tarefa "Docker ativo".** Em *check mode*, o serviço ainda não existe, e o `systemd_service` falha.
  - A correção: essa tarefa e o handler "Reiniciar o Docker" levam `when: not (ansible_check_mode and docker_pacotes is changed)`.
  - A segunda corrida deu `ok=15 changed=5 failed=0 skipped=2`.
- O servidor tem 17 pacotes por atualizar. Isso não é deste P: as atualizações automáticas são da base completa do plano geral.

**23/10, passos 4 e 5 (autorizados pelo dono):**
- Durante a corrida, ficou aberta uma ligação SSH de segurança: um *control master* do agente, em `~/.ansible/cp/guarda-loja`, fechado no fim.
- **A corrida a sério deu `ok=17 changed=6 failed=0`.** O SSH, o `ufw` e o netplan ficaram `ok`, e o handler reiniciou o Docker uma vez.
- **A segunda corrida deu `changed=0`.**

**23/10, aceitação:**
- O Docker 29.1.3 está instalado, com o *logging driver* `json-file`. O `daemon.json` tem os limites, e o Compose é o 2.40.3.
- O serviço `docker` está `enabled` e `active`.
- O fuso é `Europe/Lisbon` (WEST).
- `/opt/daciaramella/` e as suas três pastas (`anterior/`, `caddy/` e `releases/`) são root:root, 0750.
- O `mciaramella` não está no grupo `docker`.
- O `ufw` ficou igual.
- Do Mac, uma ligação SSH nova entra, e o SSH por password dá `Permission denied (publickey)`.
- **Reiniciar o servidor:** feito pelo dono a 23/10. O servidor arrancou às 09:19:13, e o Docker voltou `active` sozinho.

**Achado de 23/10, deixado para depois pelo dono** (está em "Fora desta fase", no ESTADO):
- O `mciaramella` está no grupo `lxd`, onde o instalador do Ubuntu o põe.
- O LXD não está instalado, mas o pacote `lxd-installer` está, com o `lxd-installer.socket` ativo. Quem está no grupo `lxd` pode fazê-lo instalar o LXD e, com ele, chegar a root sem password, como no grupo `docker`.
- O *socket* é o `/run/lxd-installer.socket`, de root:lxd com 0660. O `/usr/sbin/lxc` liga-se a ele para pedir a instalação, que corre como root.
- **Remover o `lxd-installer` não serve:** o `apt-get -s purge lxd-installer` mostra que levaria também o `ubuntu-server`, o metapacote da base do Ubuntu Server, de que ele é dependência.

## Aceitação

- `docker info` e `docker compose version` funcionam com `sudo`.
- `docker info --format '{{.LoggingDriver}}'` mostra `json-file`, e o `daemon.json` tem os limites.
- `timedatectl` mostra `Europe/Lisbon`.
- O SSH por password continua recusado: `ssh -o PubkeyAuthentication=no mciaramella@10.77.0.10` dá `Permission denied (publickey)`.
- A segunda corrida dá `changed=0`.
- Depois de reiniciar o servidor, o Docker está ativo (`systemctl is-active docker`).

## Riscos

- **Trancar o acesso** por um erro no `sshd` ou no `ufw`. A mitigação é o `--check --diff` antes, a sessão SSH aberta durante a corrida e, em último caso, a consola na bancada.
- **O Docker passa por cima do `ufw` nas portas que publica.** Nesta fase só a 443 é publicada (P5), e de propósito. A firewall definitiva (nftables) é de outra fase.
- **O Docker do Ubuntu pode vir numa versão mais antiga** do que a do Mac. Basta que suporte `pull_policy` e `healthcheck`, o que qualquer Compose v2 faz.
