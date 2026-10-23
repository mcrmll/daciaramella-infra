# P7 — Deploy com cópia de rollback

Estado: feito a 23/10 · Depende de: P6 · Bloqueia: P8, P9 · Executa: agente e dono · Máquinas: Mac mini → servidor

## Objetivo

O deploy de uma versão nova, quando falha, volta sozinho à versão anterior, com a base de dados e a configuração exatamente como estavam (D3, D8).

## Acertos aceites pelo dono a 23/10

1. **A etiqueta a conferir é a `version` da imagem** (= o `app_tag`), e já não o commit (`revision`), porque as tags passaram a ser as do Git (P4).
2. **Os deploys de teste** entram com `-e app_tag=dev-…` e não se escrevem no `vars.yml` (D10). Voltar à versão oficial é correr o `deploy.yml` sem `-e`, e isso também é uma troca de versão.
3. **As versões partidas dos ensaios** (E2, E3, E4) fazem-se num **clone descartável** da app, na pasta temporária do agente, com `APP_DIR=<clone> construir.sh --test`. Em vez de ramos `ensaio/*` no repositório do dono: o Git do dono e o `dev` não são tocados.
4. **A mesma versão com outra configuração** (por exemplo, o `faturacao_emissao_ativa`) passa pelo mesmo caminho seguro: cópia, troca e confirmação. Com a mesma versão e a mesma configuração, não faz nada.
5. **O backup normal do passo 3** envia já para a R2 (`teste_loja/`).

O E1 usa o commit do dono no `dev` (`34b8f67`, "testing deployment"). Esse commit troca o `static/char_logo.png`, que não aparece na app: a web usa o `apps/web/public/figaro-*.png`, recortados à mão. A versão nova confirma-se pela etiqueta no servidor.

## O fluxo do `deploy.yml`

### 1. Verificações (não mexem em nada)

- **A versão pedida existe** de uma de duas formas:
  - o ficheiro da release está em `release_dir`, o `sha256` bate certo e a etiqueta `revision` corresponde ao `app_tag`;
  - ou a imagem já está no servidor. É o caso de voltar a uma das 3 últimas versões ([P8](P8-alavancas-depois-de-abrir.md)).

  Se não existir de nenhuma forma, para e diz para correr primeiro o `construir.sh`.
- **Se o servidor já estiver nessa tag, com a mesma configuração,** não faz nada e diz porquê.
- **Janela, só com `janela_ativa: true` (D15):**
  - hora de Lisboa, lida no servidor: das 01:00 às 06:00 todos os dias, e segunda e terça o dia todo;
  - recusa entre as 04:15 e as 04:45;
  - fora da janela, só com `-e fora_da_janela=sim`;
  - aviso, sem bloquear, se não for segunda (D7).
- **A versão atual está saudável.** Se não estiver, para, a não ser com `-e forcar=sim`.
- **Espaço livre:** pelo menos 5 GB.

Para ensaiar a verificação da janela, `-e agora_ensaio="AAAA-MM-DDTHH:MM"` substitui a hora do servidor.

### 2. Enviar e carregar

Só se o servidor ainda não tiver a imagem: copia o ficheiro, faz `docker load` e apaga o ficheiro (D2). Não mexe na loja.

### 3. Backup cifrado normal

`docker compose exec -T backup /app/backup.sh`. Se falhar, avisa e continua: a proteção do deploy é a cópia do passo 6. Este backup protege de um desastre, como o disco avariar.

### 4. Guardar o pacote atual

Copia `compose.yml`, `.env`, `Caddyfile` e um ficheiro `tag` para `/opt/daciaramella/anterior/` (D8).

### 5. Parar a app

`docker compose stop app backup`. O `CREATE DATABASE … TEMPLATE` exige que ninguém esteja ligado à base de dados.

### 6. Cópia de rollback

O playbook liga-se pelo `docker compose exec -T postgres psql -U daciaramella -d postgres`:

```sql
DROP DATABASE IF EXISTS rollback_<tag_antiga>;   -- a cópia do deploy anterior
CREATE DATABASE rollback_<tag_atual> TEMPLATE daciaramella;
```

Se a cópia falhar, o deploy para aqui, volta a arrancar a versão atual e termina com erro.

### 7. Trocar a versão

Valida o compose (tarefa `validar` do P5), escreve o pacote novo e corre `docker compose up -d`.

### 8. Esperar

Até 2 minutos pelo estado `healthy`, e depois o pedido pelo Caddy (como no P6).

### 9a. Se correu bem

- Escreve uma linha no `deploys.log`: data, tag anterior, tag nova e `ok`.
- Apaga as imagens `app` e `backup` antigas, mas guarda as 3 últimas tags.
- Lista as bases de dados `falhado_*` que ainda existam, como aviso.
- Lembra a lista de verificação ([P9](P9-guia-e-ensaio-geral.md)).

A cópia `rollback_<tag_atual>` fica até ao deploy seguinte. É ela que o [P8](P8-alavancas-depois-de-abrir.md) usa para voltar atrás ainda na mesma noite.

### 9b. Se falhou: reposição automática

1. Guarda os logs da `app` no Mac, em `{{ release_dir }}/logs/deploy-<data>-<tag_nova>.log`.
2. `docker compose stop app backup`.
3. Troca as bases de dados:

   ```sql
   ALTER DATABASE daciaramella RENAME TO falhado_<tag_nova>;
   ALTER DATABASE rollback_<tag_atual> RENAME TO daciaramella;
   ```

4. Repõe o pacote de `anterior/`.
5. `docker compose up -d` e espera pelo `healthy`.
6. Escreve uma linha no `deploys.log` e termina **com erro**: "deploy de X falhou; voltou para Y".
7. **Se a versão anterior também não arrancar:** para, mostra o estado das bases de dados e dos contentores, e não tenta mais nada. O que fazer a seguir está no guia ([P9](P9-guia-e-ensaio-geral.md)).

## Passos

1. **(agente) Completar o `deploy.yml`.** O modo de instalação do P6 continua a funcionar quando não existe `compose.yml`.
2. **(agente, repositório da app) Ramos descartáveis para os ensaios,** que nunca se juntam à `main` e se apagam no fim. Cada um precisa de um commit, para o `construir.sh` ter o que construir, e esses commits são feitos ou autorizados pelo dono:
   - `ensaio/boa`: só muda um texto;
   - `ensaio/arranque-falha`: um `throw` na primeira linha do `index.ts`, antes das migrações;
   - `ensaio/migracao-e-falha`: uma migração que cria a tabela `ensaio_rollback`, e um `throw` logo a seguir a `aplicarMigrations()`;
   - `ensaio/aditiva`: uma migração que só acrescenta uma coluna com `DEFAULT` (é para o P8).

   A imagem de cada um faz-se com o `construir.sh --test`, que só lê o `dev`: rever no P7 como pôr o commit de ensaio no `dev` sem o deixar lá. Os `throw` não partem o `npm test`, porque os testes não importam o `index.ts`.
3. **(o dono autoriza) Ensaios no servidor de testes.**
4. **(agente) Limpar no fim:**
   - apagar as bases `falhado_*` dos ensaios;
   - apagar as imagens `ensaio` no servidor e no Mac, e os ficheiros de release desses ramos;
   - apagar os ramos `ensaio/*`;
   - voltar à tag de `main`.

## Aceitação

Antes de cada ensaio, contar as comandas (`select count(*) from comandas`), as linhas de `drizzle.__drizzle_migrations` e o `sha256` do `.env`.

- **E1, versão boa** (`ensaio/boa`):
  - o deploy corre bem;
  - existe `rollback_<tag anterior>`;
  - o `anterior/` tem o pacote antigo;
  - há uma linha `ok` no `deploys.log`;
  - a pasta `releases/` está vazia.
- **E2, falha antes das migrações** (`ensaio/arranque-falha`):
  - volta sozinho e termina com erro;
  - a tag a correr é a anterior;
  - as contagens são iguais às de antes;
  - existe `falhado_<tag>`.
- **E3, falha depois de uma migração** (`ensaio/migracao-e-falha`):
  - volta sozinho;
  - a tabela `ensaio_rollback` não existe na `daciaramella`, mas existe na `falhado_<tag>`;
  - o número de linhas das migrações é igual ao de antes.
- **E4, `.env` reposto:** num ensaio de falha com uma variável a mais no modelo do `.env`, o `sha256` do `.env` no fim é igual ao de antes.
- **E5, janela:** com `-e janela_ativa=true` e `agora_ensaio` numa quarta às 15:00, ou num dia qualquer às 04:30, o deploy recusa sem mexer em nada.
- **E6, nada a fazer:** correr outra vez o deploy do E1, com a mesma tag e a mesma configuração, não envia nada, não para a app e não faz outra cópia.
- **E7, versão atual partida:** com a `app` parada à mão, o deploy recusa sem `forcar=sim`.
- **E8, versão inexistente:** com um `app_tag` sem ficheiro de release e sem imagem no servidor, o deploy recusa sem mexer em nada.

## Riscos

- **A cópia falha se houver ligações à base de dados.** Por isso a app e o backup param antes. Se mesmo assim falhar, o deploy para antes de trocar a versão.
- **A cópia está no mesmo disco da base de dados.** Não protege de uma avaria do disco; para isso há o backup cifrado do passo 3.
- **Uma versão `healthy` pode ter funções partidas,** porque o `/health` só faz `select 1`. Para isso há a lista de verificação do [P9](P9-guia-e-ensaio-geral.md).
- **Esquecer bases `falhado_*` a ocupar disco.** O deploy lista-as em cada corrida.

## Registo

**23/10, passo 1 (agente):** o `deploy.yml` passou a ter os três casos, com as tarefas partilhadas em `playbooks/tarefas/`:
- **Os casos:** instalação, troca, ou nada a fazer. A configuração nova compara-se com a instalada com `template` em `check_mode: true`.
- **Os ficheiros de tarefas:**
  - `enviar-imagens.yml` vê primeiro se as imagens já estão no servidor, e só então exige o ficheiro no Mac (para o P8);
  - `escrever-pacote.yml` escreve o pacote;
  - `arrancar.yml` faz o `compose up --wait` e o `/health` pelo Caddy.
- **A troca:**
  - verificações: a janela, só com `janela_ativa`; a versão atual `healthy`, ou `forcar=sim`; e 5 GB livres;
  - o backup normal, que avisa se falhar e continua;
  - o `anterior/` (`compose.yml`, `Caddyfile`, `.env`, `rclone.conf` e `tag`);
  - `stop app backup`;
  - `DROP` das `rollback_*` antigas, corte das ligações e `CREATE DATABASE "rollback_<atual>" TEMPLATE daciaramella`, com o seu próprio `rescue`, que volta a arrancar e para;
  - `block` (escrever, arrancar e confirmar, `deploys.log`), cujo `rescue` faz:
    1. guarda os logs no Mac;
    2. `daciaramella` → `falhado_<nova>` e `rollback_<atual>` → `daciaramella`;
    3. repõe o `anterior/` e arranca;
    4. escreve no `deploys.log` e termina com erro.

    Se a reposição também falhar, mostra o estado e para.
  - Depois de uma troca boa: guarda as 3 últimas imagens, avisa das `falhado_*` e lembra a lista de verificação.

**23/10, ensaios (autorizados pelo dono: "ok aceito e go"):**
- **Antes:** 2 comandas, 14 migrações, `.env` `17abd03c…`, e só a BD `daciaramella`.
- **E1, versão boa** (`dev-2026-10-23-1638`, do commit `34b8f67` do dono):
  - o `--check --diff` mostrou "Troca: v0.1.0 → dev-…" e só as duas linhas das imagens;
  - a sério: `ok=61 changed=21 failed=0`, em 56 s;
  - o backup normal subiu à R2 (`upload: ok`), o que prova a R2 do servidor antes das 04:30;
  - **aceitação:** a `app` `dev-…` está `healthy`; existe a `rollback_v0.1.0`; o `anterior/` tem a `v0.1.0`; o `deploys.log` tem "troca v0.1.0 → dev-2026-10-23-1638 ok 34b8f67…"; a `releases/` está vazia; e as contagens e o `.env` estão iguais.
- **E6, nada a fazer** (o mesmo comando outra vez):
  - "Nada a fazer: o servidor já está na dev-2026-10-23-1638, com a mesma configuração.";
  - 13 s, só com a validação; a app não parou; não há linha nova no `deploys.log`; e continua a haver uma só `rollback_`.
- **E5, janela** (`-e app_tag=v0.1.0 -e janela_ativa=true`):
  - com `agora_ensaio='2026-10-28 15:00'` (quarta-feira), recusou com "Fora da janela de manutenção";
  - com `'2026-10-26 04:30'` (segunda-feira), recusou com "Entre as 04:15 e as 04:45 corre o backup";
  - nada mudou: o `deploys.log` e o `StartedAt` da app ficaram iguais.
- **E7, versão atual partida:** com a `app` parada à mão, recusou com "A versão atual (dev-2026-10-23-1638) não está saudável… só avança com -e forcar=sim". A app voltou a arrancar à mão (`docker compose start app`, `healthy`).
- **E8, versão inexistente** (`v9.9.9`): recusou na tarefa das imagens, com "não estão no servidor, e falta daciaramella-v9.9.9.tar.zst… Correr primeiro o construir.sh". Nada mudou.
- **As versões partidas, em clones descartáveis** (`git clone --branch dev` para a pasta temporária, `APP_DIR=<clone> construir.sh --test`). Só rebentam com `NODE_ENV=production`, por isso os testes passam:
  - **E2** = `dev-2026-10-23-1646` (`1730c4c`): `throw` no arranque, antes das migrações;
  - **E3** = `dev-2026-10-23-1647` (`5bd3952`): migração `0014_ensaio_rollback` (`CREATE TABLE ensaio_rollback`, no `_journal.json`) e um `throw` logo a seguir ao `aplicarMigrations()`.
- **E2, falha no arranque:** saiu com erro, em 75 s, com "O deploy de dev-2026-10-23-1646 falhou em «Arrancar…» e voltou sozinho para a dev-2026-10-23-1638…".
  - Os logs da app no Mac (`logs/deploy-20261023-1650-dev-2026-10-23-1646.log`) mostram o `Error: ensaio E2`.
  - **Aceitação:** a `dev-2026-10-23-1638` está `healthy`; 2 comandas e 14 migrações, como antes; o `.env` igual; existe a `falhado_dev-2026-10-23-1646`; e o `deploys.log` diz "FALHOU (…); voltou para dev-2026-10-23-1638".
- **E3, falha depois de uma migração:** saiu com erro, em 76 s, e voltou sozinho.
  - **Aceitação:** a `daciaramella` não tem a `ensaio_rollback` e tem 14 migrações; a `falhado_dev-2026-10-23-1647` tem a `ensaio_rollback` e 15 migrações. A migração aconteceu e a cópia desfê-la.
- **E4, `.env` reposto:** com o `env.j2` a ter, só durante o ensaio, uma linha `ENSAIO_E4='1'` (reposto pelo Git logo a seguir), e a versão do E2.
  - O `.env` novo chegou a ser escrito (`changed`); a falha e a reposição aconteceram.
  - **Aceitação:** o `.env` voltou ao `17abd03c…`, sem a `ENSAIO_E4`.
- **De volta à `v0.1.0`** (`deploy.yml` sem `-e`): "Troca: dev-2026-10-23-1638 → v0.1.0", `failed=0`, em 49 s.
  - O backup subiu à R2.
  - Avisou das duas `falhado_*`.
  - Ficou a `rollback_dev-2026-10-23-1638`.
  - A app está `healthy` e os dados e o `.env` estão iguais.
- **Segredos:** em todos os registos dos ensaios, zero linhas com valores do `.env`, do `rclone.conf` ou da chave da raiz.
- **Limpeza (passo 4):**
  - no servidor: apagadas as `falhado_dev-2026-10-23-1646` e `…-1647`, e as imagens dessas duas tags;
  - no Mac: apagados os ficheiros de release e as imagens dessas tags, e os clones;
  - ficaram, de propósito: no servidor, a `v0.1.0`, a `dev-2026-10-23-1638`, a `rollback_dev-2026-10-23-1638` e as imagens de base; no Mac, os três logs dos ensaios, em `~/daciaramella-releases/logs/`;
  - o repositório da app não foi tocado (`dev` em `34b8f67`, sem *worktrees* a mais).
- **Nota para o P8 e o P9:** depois de um deploy que falhou e voltou, a cópia `rollback_` da versão atual já não existe, porque foi ela que voltou a ser a `daciaramella`. Só há uma nova no deploy seguinte.
