# P1 — Mac mini pronto para o Ansible

Estado: feito a 18/10 · Depende de: — · Bloqueia: P2, P5 a P9 · Executa: dono e agente (cada passo diz quem) · Máquinas: Mac mini

## Objetivo

- A app deixa de correr no Mac mini (D2).
- O Mac mini fala com o servidor por Ansible, com sudo.
- Os segredos da instalação estão num Vault cifrado.

## Passos

### Passo 1 — parar a simulação da app (dono)

1. Na pasta da app, correr `docker compose down` **sem `-v`**, para os dados ficarem no disco até o dono decidir apagá-los.
2. **O Docker fica instalado.** Continua a servir para construir as imagens (P4) e para os contentores temporários dos testes e do drill de restauro.
3. O último backup da simulação já está na pasta `simulacao/` da R2, bloqueado durante 90 dias.
4. Anotar a data no [ESTADO](../ESTADO.md).

### Passo 2 — instalar o Ansible (dono)

1. `brew install ansible`.
2. Anotar no [ESTADO](../ESTADO.md) a versão (`ansible --version`) e a do `community.docker` (`ansible-galaxy collection list community.docker`).

### Passo 3 — estrutura no repositório (agente)

```text
ansible/
  ansible.cfg
  vault-pass.sh                         # lê a password do Vault do Porta-chaves (D18)
  inventario/loja.yml
  inventario/group_vars/loja/vars.yml
  inventario/group_vars/loja/vault.yml  # cifrado; criado pelo dono no passo 4
  playbooks/
  modelos/
```

- **`inventario/loja.yml`:** um grupo `loja` com o host `elitedeskserver`, `ansible_host: 10.77.0.10` e `ansible_user: mciaramella`. Nesta fase, o Ansible liga-se sempre pela rede da loja. O Tailscale fica para depois (D13).
- **`vars.yml`:**
  - `app_tag: ""`, que fica vazio até ao P6;
  - `release_dir: ~/daciaramella-releases`, onde o `construir.sh` deixa as imagens e os playbooks deixam os logs (`logs/`);
  - `janela_ativa: false` (D15);
  - `ansible_become_password: "{{ vault_become_password }}"` (D16);
  - `ansible_become_exe: sudo.ws`, acrescentado a 18/10.
    - No 26.04, o `sudo` é o `sudo-rs`, e o `become` falhava por timeout à espera da pergunta da password.
    - O sudo clássico (`sudo.ws`) funciona e lê o mesmo `/etc/sudoers`.
    - Testado primeiro com `-e ansible_become_exe=sudo.ws`.
- **`ansible.cfg`:**
  - aponta para o inventário;
  - `vault_password_file = vault-pass.sh`;
  - `interpreter_python = auto_silent`.
- **`vault-pass.sh`:** só faz `security find-generic-password -a daciaramella-infra -s ansible-vault -w`. Não guarda nada em disco.
- **`.gitignore` na raiz do repositório:** `*.decifrado`, `*.retry` e `.DS_Store`.

### Passo 4 — Vault e segredos (dono, no Terminal, fora do VS Code)

1. Guardar a password do Vault no Porta-chaves: `security add-generic-password -a daciaramella-infra -s ansible-vault -w`. O comando pede a password, por isso ela não fica no histórico do shell.

   O `security` criou a entrada e fica na lista de acesso, por isso lê a password sem perguntar (D18). Qualquer programa que corra como o dono, incluindo o agente, consegue decifrar o Vault em silêncio. O dono testou a confirmação obrigatória a 18/10 e preferiu não ter uma janela por comando.
2. Guardar a mesma password no cofre de passwords. É a única cópia fora do Mac mini.
3. `ansible-vault create inventario/group_vars/loja/vault.yml`, com estas variáveis (os nomes podem ir para o Git; os valores, nunca):
   - `vault_become_password`: a password do `sudo` do `mciaramella` no servidor;
   - `vault_postgres_password`: nova, gerada com `openssl rand -base64 24`;
   - `vault_admin_password_inicial`: pelo menos 10 caracteres;
   - `vault_moloni_client_id` e `vault_moloni_client_secret`: os da conta de testes;
   - `vault_moloni_chave_cifra`: nova para esta instalação, gerada com `openssl rand -hex 32`;
   - `vault_age_public_key`: a chave pública definitiva (fase 7 da app, D3).

   O P6 acrescenta a raiz do Caddy.
4. Nunca usar `ansible-vault decrypt` para um ficheiro em disco. Para mudar o Vault, só `ansible-vault edit`.

## Aceitação

- `docker ps` no Mac mini não mostra nenhum contentor da app.
- `ansible loja -m ping` responde `pong`.
- `ansible loja -b -m command -a whoami` responde `root`. Prova o `sudo` com a password do Vault, sem a escrever.
- `head -1 ansible/inventario/group_vars/loja/vault.yml` mostra `$ANSIBLE_VAULT;1.1;AES256`.
- `git status` não mostra nenhum ficheiro decifrado.
- A password do Vault está no cofre de passwords do dono.

## Riscos

- **Perder a password do Vault** é perder os segredos da instalação. Os da Moloni recuperam-se no portal da Moloni, mas a `MOLONI_CHAVE_CIFRA` não: sem ela, é preciso entrar outra vez na Moloni. A mitigação é o passo 4.2.
- **O agente consegue decifrar o Vault sem perguntar** (D18). A proteção é só a regra: o agente nunca mostra valores do Vault e pede autorização antes de correr comandos contra o servidor.
- **Commitar um ficheiro decifrado por engano.** A mitigação é só usar `ansible-vault edit` e conferir o `head -1` antes de cada commit.
- **A simulação do Mac mini para, e com ela os envios para a `simulacao/` da R2.** Quem os retoma é a Q1 do [ESTADO](../ESTADO.md).
