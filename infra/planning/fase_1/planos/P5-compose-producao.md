# P5 — Compose de produção

Estado: por fazer · Depende de: P4 · Bloqueia: P6 · Executa: agente · Máquinas: Mac → servidor

## Objetivo

O compose que vai correr no servidor existe como modelo Ansible neste repositório e é válido no servidor. O compose da app continua a ser o de desenvolvimento, que hoje ninguém corre (D2). O arranque a sério prova-se no [P6](P6-primeira-instalacao.md).

## Ficheiros (em `infra/ansible/modelos/`)

- `compose.yml.j2`
- `env.j2`, preenchido a partir do Vault
- `Caddyfile.j2`

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
   - `RCLONE_REMOTE` vazio e sem a pasta do rclone montada, até à decisão da Q1 do [ESTADO](../ESTADO.md);
   - o resto como na app (`BACKUP_HORA`, `RETENCAO_LOCAL` e `AGE_PUBLIC_KEY`).
10. **Sem o serviço `restauro` nesta fase.** Volta com o `restauro.yml`, numa fase seguinte, e sem montar sempre a pasta da chave.
11. **Rede: a de omissão, com saída para a internet.** A app precisa dela para a Moloni, e ainda não há proxy. A rede interna sem saída entra com o proxy, na Fase 2 do plano geral.

## Passos

1. **(agente)** Escrever os três modelos.
2. **(agente)** Uma tarefa `validar` no `deploy.yml` (que o P6 escreve), que corre antes de qualquer arranque: preenche os modelos numa pasta temporária no servidor e corre `docker compose config --quiet`.
3. **(agente, com autorização)** Correr só a validação contra o servidor (`--tags validar`).

## Aceitação

- No servidor, com os valores do Vault, `docker compose config --quiet` passa.
- Com um `.env` de ensaio sem a password do Postgres, falha com a mensagem do `${VAR:?}`.
- O compose preenchido tem um `pull_policy: never` por serviço e nenhum `ports:` fora do Caddy (`docker compose config` e `grep`).
- O resto prova-se no [P6](P6-primeira-instalacao.md): `healthy`, portas fechadas, nenhuma descarga de imagens e HTTPS.

## Riscos

- **Um erro só se vê no arranque,** porque o `docker compose config` valida a forma e não o funcionamento. O P6 é o ensaio a sério, e o servidor de testes pode reinstalar-se do zero (D5).
