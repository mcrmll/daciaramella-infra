# P5 — Compose de produção

Estado: feito a 23/10 · Depende de: P4 · Bloqueia: P6 · Executa: agente · Máquinas: Mac → servidor

## Objetivo

O compose que vai correr no servidor existe como modelo Ansible neste repositório e é válido no servidor. O compose da app continua a ser o de desenvolvimento, que hoje ninguém corre (D2). O arranque a sério prova-se no [P6](P6-primeira-instalacao.md).

## Ficheiros (em `ansible/modelos/`)

- `compose.yml.j2`
- `env.j2`, preenchido a partir do Vault
- `Caddyfile.j2`
- `rclone.conf.j2`, preenchido a partir do Vault (Q1)

## Diferenças face ao compose da app

1. **`name: daciaramella` no topo.** Os volumes chamam-se sempre `daciaramella_*`, seja qual for a pasta.
2. **`image:` com tag, em vez de `build:`:**
   - `daciaramella/app:{{ app_tag }}` e `daciaramella/backup:{{ app_tag }}`;
   - o Postgres e o Caddy com as tags locais do P4.
3. **`pull_policy: never` em todos os serviços (D17).** O `up` nunca vai buscar imagens: chegam todas do Mac.
4. **Sem `ports:` no Postgres nem na app.** Só o Caddy publica a 443.
5. **`${VAR:?}` em todas as passwords e chaves.** O compose falha se faltar alguma.
6. **Variáveis da app que o compose de desenvolvimento não passa:**
   - `FATURACAO_REAL_ATIVA`, que fica a `0` no servidor de testes;
   - `MOLONI_ORIGEM_GESTAO=https://{{ app_nome }}`.

   Também passam `FATURACAO_EMISSAO_ATIVA`, `MOLONI_HTTP_ATIVO`, `MOLONI_CLIENT_ID`, `MOLONI_CLIENT_SECRET`, `MOLONI_CHAVE_CIFRA` e `ADMIN_PASSWORD_INICIAL`. A `FATURACAO_EMISSAO_ATIVA` vem da variável `faturacao_emissao_ativa` do `vars.yml` ([P8](P8-alavancas-depois-de-abrir.md)).
7. **Healthcheck na app:**

   ```yaml
   healthcheck:
     test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:3000/health"]
     interval: 5s
     timeout: 3s
     retries: 3
     start_period: 60s
   ```

   O `wget` vem com o BusyBox da imagem alpine. Se não vier, usar `node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"`.
8. **Caddy:**
   - publica `443:443`, para a rede da loja;
   - monta o `Caddyfile` e `/opt/daciaramella/caddy/data:/data`. É uma pasta normal e não um volume, para o Ansible poder pôr lá a raiz ([P6](P6-primeira-instalacao.md));
   - o `Caddyfile`:

     ```text
     {{ app_nome }} {
       tls internal
       reverse_proxy app:3000
     }
     ```

9. **Backup:**
   - imagem com a tag da release;
   - envia para a R2 (Q1 do [ESTADO](../ESTADO.md)), com `RCLONE_REMOTE={{ rclone_remote }}`:
     - no `vars.yml`, `rclone_remote: r2:daciaramella-backups/teste_loja`, enquanto o servidor estiver na bancada;
     - passa a `…/loja` quando o servidor for para a loja;
   - monta `/opt/daciaramella/rclone/` (root, 0700) em `/config/rclone`, como na app;
   - lá dentro, o `rclone.conf` (0600) sai do `rclone.conf.j2`:
     - a secção `[r2]` é igual à do `docs/backup-restauro.md` da app, com `no_check_bucket = true` e o `endpoint` com `.eu.`;
     - os valores vêm do Vault: `vault_r2_access_key_id`, `vault_r2_secret_access_key` e `vault_r2_account_id`;
   - o resto como na app (`BACKUP_HORA`, `RETENCAO_LOCAL` e `AGE_PUBLIC_KEY`).
10. **Sem o serviço `restauro` nesta fase.** Volta com o `restauro.yml`, numa fase seguinte, e sem montar sempre a pasta da chave.
11. **Rede: a de omissão, com saída para a internet.** A app precisa dela para a Moloni, e ainda não há proxy. A rede interna sem saída entra com o proxy, na Fase 2 do plano geral.

## Segredos nos modelos

- **O `.env` e o `rclone.conf` levam segredos do Vault.** As tarefas que os escrevem têm `diff: false` e `no_log: true`. Assim, nem o `--diff` nem os erros mostram o conteúdo no ecrã, e o agente, que corre os playbooks, não vê os valores.
- **No servidor ficam root, 0600**, numa pasta 0750 ou 0700.
- **Para confirmar que mudaram**, o agente olha só para o `changed` e para o `sha256` do ficheiro, nunca para o conteúdo.

## Passos

0. **(dono, no Terminal)** Juntar ao Vault, com `ansible-vault edit`, os três valores da R2: `vault_r2_access_key_id`, `vault_r2_secret_access_key` e `vault_r2_account_id`.
   - Reaproveita-se o token de leitura e escrita que a simulação usava (decisão do dono, 23/10). A máquina que envia passa a ser o servidor.
   - Os valores estão na secção `[r2]` do `ops/rclone/rclone.conf` da app, no Mac mini, que fica fora do Git. O *account id* é a parte do `endpoint` antes de `.eu.r2.cloudflarestorage.com`.
1. **(agente)** Escrever os quatro modelos.
2. **(agente)** Uma tarefa `validar` no `deploy.yml` (que o P6 escreve), que corre antes de qualquer arranque: preenche os modelos numa pasta temporária no servidor e corre `docker compose config --quiet`.
3. **(agente, com autorização)** Correr só a validação contra o servidor (`--tags validar`).

## Aceitação

- No servidor, com os valores do Vault, `docker compose config --quiet` passa.
- Com um `.env` de ensaio sem a password do Postgres, falha com a mensagem do `${VAR:?}`.
- O compose preenchido tem um `pull_policy: never` por serviço e nenhum `ports:` fora do Caddy (`docker compose config` e `grep`).
- O resto prova-se no [P6](P6-primeira-instalacao.md): `healthy`, portas fechadas, nenhuma descarga de imagens e HTTPS.

## Riscos

- **Um erro só se vê no arranque,** porque o `docker compose config` valida a forma e não o funcionamento. O P6 é o ensaio a sério, e o servidor de testes pode reinstalar-se do zero (D5).

## Registo

**23/10, passo 0 (dono):** os valores da R2 estão no Vault: `vault_r2_access_key_id`, `vault_r2_secret_access_key`, `vault_r2_account_id` e, por iniciativa do dono, `vault_r2_endpoint`. O `rclone.conf.j2` usa o `vault_r2_endpoint` diretamente, porque é o valor exato que funcionava. O `vault_r2_account_id` fica sem uso.

**23/10, passos 1 e 2 (agente):**
- **Modelos em `ansible/modelos/`:** `compose.yml.j2`, `env.j2`, `Caddyfile.j2` e `rclone.conf.j2`.
- **Variáveis novas no `vars.yml`:** `faturacao_emissao_ativa: 1`, `faturacao_real_ativa: 0`, `moloni_http_ativo: 1`, `backup_hora`, `retencao_local` e `rclone_remote: r2:daciaramella-backups/teste_loja`.
- **Decisões de pormenor:**
  - **Os segredos só no `.env`; o resto escrito diretamente no compose.** Assim, o `--diff` do compose mostra tudo o que não é segredo.
  - **O `DATABASE_URL` vem inteiro do `.env`,** com a password codificada (`urlencode` e `replace('/', '%2F')`). Uma password `base64` pode ter `/`, `+` e `=`, e o `urlencode` do Jinja2 deixa o `/` como está. Confirmado que o `pg-connection-string` da app descodifica bem.
  - **No `.env`, os valores vão entre aspas simples,** para o Compose não fazer substituições com `$`. O `deploy.yml` recusa valores do Vault com `'` ou mudanças de linha.
  - **O `rclone/` é montado só para leitura** (`:ro`).
  - **No `Caddyfile`, `skip_install_trust`:** a raiz instala-se nos postos à mão, e não dentro do contentor.
  - **O `wget` existe na imagem `v0.1.0`** (BusyBox), por isso o *healthcheck* usa-o.
- **`playbooks/deploy.yml`, só com o bloco `validar`** (`tags: validar`, `check_mode: false`). Faz, por ordem:
  1. verifica que o `app_tag` não está vazio, que o *endpoint* tem `.eu.`, que a password do admin tem pelo menos 10 caracteres e que os valores cabem entre aspas simples (estes dois últimos com `no_log`);
  2. preenche os modelos numa pasta temporária do servidor, só de root;
  3. corre `docker compose config` com um `.env` **de ensaio, com valores falsos**, para os erros se verem sem segredos;
  4. confirma o projeto `daciaramella`, o `pull_policy: never` em todos os serviços e as portas só no Caddy;
  5. confirma que, sem a password do Postgres, o compose recusa;
  6. corre `config --quiet` com o `.env` e o `rclone.conf` verdadeiros, com `no_log`;
  7. apaga a pasta temporária no `always`.
- **Validação no Mac, com valores falsos:**
  - o `--syntax-check` passou;
  - os modelos preenchem-se bem;
  - o `docker compose config` mostra 4 serviços, todos `never`, com a 443 só no Caddy;
  - sem a password, falha com "falta POSTGRES_PASSWORD no .env";
  - o `caddy validate` com a imagem 2.11.7 dá "Valid configuration".

**23/10, passo 3 (validação no servidor, autorizada pelo dono):**
- `ansible-playbook playbooks/deploy.yml --tags validar -e app_tag=v0.1.0` deu `ok=15 changed=7 failed=0`. Os `changed` são da pasta temporária.
- **Aceitação:**
  - o compose é válido com os valores do Vault;
  - o `.env` de ensaio sem a password falha com a mensagem do `${VAR:?}`;
  - há um `pull_policy: never` por serviço e portas só no Caddy, conferidos pelo `assert` sobre o `config --format json`.
- Depois da corrida, não sobrou nenhuma pasta `/tmp/ansible.*validar`, o `/opt/daciaramella` ficou igual e não há contentores.
- O que falta provar (`healthy`, portas, nenhuma descarga, HTTPS) é do P6.
