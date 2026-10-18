# P2 — Base mínima do servidor (`base.yml`, versão 1)

Estado: por fazer · Depende de: P1 · Bloqueia: P3, P5, P6 · Executa: agente, com autorização do dono para correr contra o servidor · Máquinas: Mac mini → servidor

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
