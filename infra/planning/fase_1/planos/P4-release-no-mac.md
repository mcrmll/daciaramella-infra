# P4 — Release no Mac

Estado: feito a 23/10 · Depende de: — · Bloqueia: P5, P6 · Executa: agente (repositórios da app e da infra); o dono autoriza os builds · Máquinas: Mac mini

## Objetivo

- **Todo o contacto com a internet do build é do Mac (D1).** Um só script, o `construir.sh`, produz a partir de um commit um ficheiro com as imagens x86 prontas a enviar. Tem dois modos (decidido pelo dono a 23/10):
  - `--test`: o último commit do ramo `dev` local, para experimentar no servidor;
  - `--release <tag>`: uma *tag* da `main` do GitHub, para uma versão.
- **O servidor nunca recebe o código (D2).** As imagens levam só o que é preciso para correr.
- **As imagens de terceiros (Postgres e Caddy) seguem o mesmo caminho,** fixadas por digest (D17).

## Passos

### Passo 1 — Node fixo (agente, repositório da app, no `dev`)

- No `Dockerfile`, trocar `node:26-alpine` pela versão exata, `node:26.7.0-alpine`, nos dois `FROM`. É a mesma versão do Node do Mac (`node --version` a 23/10).
- Assim, reconstruir o mesmo commit noutro dia dá sempre o mesmo Node. O `engines` do `package.json` pode continuar `26.x`.

### Passo 2 — `ops/testar.sh` (agente, repositório da app, no `dev`)

O `npm test` precisa de um Postgres. Como a app não corre no Mac (D2), o script cria um Postgres temporário, só para os testes:

```sh
docker run -d --rm --name daciaramella-testes-pg \
  -e POSTGRES_USER=daciaramella -e POSTGRES_PASSWORD=testes -e POSTGRES_DB=daciaramella \
  -p 127.0.0.1:55432:5432 --tmpfs /var/lib/postgresql/data \
  postgres:17.11-alpine
```

1. Espera pelo `pg_isready` pelo TCP (`-h 127.0.0.1`). Durante o arranque, o servidor temporário do initdb só escuta no socket local. A BD tem de ser a `daciaramella`, porque os testes ligam-se a ela para criarem a `daciaramella_test` (`apps/server/src/testes/bd.ts`).
2. Corre `DATABASE_URL_TEST=postgres://daciaramella:testes@127.0.0.1:55432/daciaramella_test npm test`. Se receber outro comando, corre esse: por exemplo `ops/testar.sh npm run test:server -- -t '<padrão>'`.
3. Apaga o contentor no fim, passem ou falhem os testes (`trap … EXIT`).

- Os dados ficam em memória e desaparecem.
- A porta 55432 só escuta no próprio Mac.
- É o mesmo script para os agentes no dia a dia e para o `construir.sh`.

### Passo 3 — `infra/scripts/construir.sh` (agente, repositório da infra)

Fica na infra porque nunca usa a pasta de trabalho da app: lê os commits do repositório (`APP_DIR`, por omissão `~/business/da_ciaramella/system/daciaramella-system`). Podes estar em qualquer ramo, com ficheiros por commitar, e nada disso entra.

| | `construir.sh --test` | `construir.sh --release v0.1.0` |
|---|---|---|
| **Código** | o último commit do ramo `dev` local (`git rev-parse dev`). O que não estiver commitado não entra | a *tag* indicada, depois de um `git fetch origin --tags`. Pode ser a atual ou uma mais antiga |
| **Recusa se** | — | a *tag* não existir, ou não estiver na `main` do GitHub (`git merge-base --is-ancestor <tag> origin/main`) |
| **Etiqueta da imagem** | `dev-<data-hora>`, legível, na hora do Mac: `dev-2026-10-23-1530` | a *tag*: `v0.1.0` |
| **Ficheiro** | `daciaramella-dev-2026-10-23-1530.tar.zst` | `daciaramella-v0.1.0.tar.zst` |

Em ambos os modos:

1. **Uma cópia limpa** do commit escolhido numa pasta temporária (`git worktree add --detach`), apagada no fim, corra bem ou mal.
2. **Testes nessa cópia:** `npm ci` e depois o `ops/testar.sh` dessa cópia. Se falharem, para. Uma *tag* sem `ops/testar.sh` (a `v0.0.0`, por exemplo) é recusada.
3. **As duas imagens,** para `linux/amd64`:

   ```sh
   docker buildx build --platform linux/amd64 --load \
     --label org.opencontainers.image.revision="$COMMIT" \
     --label org.opencontainers.image.version="$TAG" \
     -t daciaramella/app:"$TAG" "$COPIA"
   docker buildx build --platform linux/amd64 --load \
     --label org.opencontainers.image.revision="$COMMIT" \
     --label org.opencontainers.image.version="$TAG" \
     -f "$COPIA/ops/backup/Dockerfile" -t daciaramella/backup:"$TAG" "$COPIA"
   ```

4. **O ficheiro:**

   ```sh
   docker save daciaramella/app:"$TAG" daciaramella/backup:"$TAG" \
     | zstd -T0 > "$RELEASE_DIR/daciaramella-$TAG.tar.zst"
   shasum -a 256 "$RELEASE_DIR/daciaramella-$TAG.tar.zst" > "$RELEASE_DIR/daciaramella-$TAG.tar.zst.sha256"
   ```

   O `RELEASE_DIR` é `~/daciaramella-releases` por omissão, fora dos repositórios.
5. **No fim, mostra** o modo, a etiqueta, o commit, o caminho do ficheiro e o tempo que o build demorou.

**No deploy (P6 e P7):** uma versão vai para o `vars.yml` (`app_tag: v0.1.0`) e é commitada (D10). Um teste entra só no comando, com `-e app_tag=dev-2026-10-23-1530`, sem ficar escrito.

### Passo 4 — `infra/scripts/imagens-base.sh` (agente, repositório da infra)

Corre raramente: na primeira instalação e quando se atualiza o Postgres ou o Caddy.

1. Para cada imagem (`postgres:17.X-alpine` e `caddy:2.X-alpine`), faz `docker pull --platform linux/amd64` pelo digest.
2. Dá-lhe uma tag local: `daciaramella/postgres:17.X-<digest curto>` e `daciaramella/caddy:2.X-<digest curto>`.
3. Guarda as duas em `~/daciaramella-releases/base-<data>.tar.zst`, com o `.sha256`.
4. Os digests e as tags locais ficam no `vars.yml` (`postgres_imagem`, `caddy_imagem`), para estarem versionados.

### Passo 5 — documentação na app (agente, repositório da app, no `dev`)

O `CLAUDE.md` passa a dizer:
- **a app não corre no Mac (D2).** Saem os comandos que a põem a correr localmente (`docker compose up -d --build` e os `npm run db:*` contra uma base de dados local);
- **os testes correm com `ops/testar.sh`;**
- **a regra das migrações como boa prática (D6);**
- **as imagens fazem-se no repositório da infra,** com `construir.sh --test` (do `dev`) ou `--release <tag>` (da `main`), e o deploy também.

Os outros documentos da app que assumem a app a correr no Mac ficam para depois ([ESTADO](../ESTADO.md), "Fora desta fase").

### Passo 6 — primeiros builds (o dono autoriza; o agente corre)

1. Com os passos 1, 2 e 5 commitados pelo dono no `dev`: `construir.sh --test`.
2. Depois do *pull request* para a `main` e de uma *tag* nova criada pelo dono (por exemplo `v0.1.0`): `construir.sh --release v0.1.0`.
3. Anotar no [ESTADO](../ESTADO.md) as etiquetas e o tempo dos builds.

## Aceitação

- **`testar.sh`:**
  - no fim não sobra o contentor, passem ou falhem os testes (`docker ps -a --filter name=daciaramella-testes-pg` sai vazio);
  - com um filtro, corre só esses testes.
- **`construir.sh --test`:**
  - com um ficheiro por commitar na pasta da app, a imagem não o leva: só entra o último commit do `dev`;
  - com um teste partido num commit do `dev`, não constrói nada;
  - a etiqueta é `dev-<data-hora>`.
- **`construir.sh --release`:**
  - recusa uma *tag* que não existe, uma que não está na `main` e a `v0.0.0` (sem `testar.sh`);
  - com uma *tag* válida, produz o `.tar.zst` e o `.sha256`.
- **As imagens:**
  - `docker image inspect daciaramella/app:<etiqueta> --format '{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}'` mostra `amd64 <commit completo>`;
  - o `NODE_VERSION` em `docker image inspect daciaramella/app:<etiqueta> --format '{{.Config.Env}}'` é o 26.7.0.
- **A imagem não leva o código-fonte:** num contentor criado sem arrancar (`docker create`), o `docker export … | tar -t` não tem `apps/server/src` nem `apps/web/src`.
- **Imagens de base:** o `imagens-base.sh` produz o ficheiro com o Postgres e o Caddy em amd64, com as tags locais.
- **A pasta da app fica como estava:** o mesmo ramo, os mesmos ficheiros soltos, e sem *worktrees* a mais (`git worktree list`).

## Riscos

- **O build é emulado e mais lento.** Se passar dos 15 minutos, rever a D1.
- **Os testes correm em arm64 no Mac e a produção em amd64.** Numa app em JavaScript sem dependências nativas, as diferenças são raras. O ensaio a sério é no servidor ([P6](P6-primeira-instalacao.md)).
- **Um ficheiro de release é grande** (centenas de MB descomprimido). O `zstd` reduz bastante. Os ficheiros antigos no Mac apagam-se à mão.
- **Quando o servidor for para a loja, um `--test` vai para o servidor da loja.** Decide-se nessa altura onde se testa.

## Registo

**23/10, passos 1, 2 e 5 (agente, no `dev` da app, por commitar pelo dono):**
- **`Dockerfile`:** `node:26.7.0-alpine` nos dois `FROM`. A tag existe no Docker Hub e é a versão do Node do Mac.
- **`ops/testar.sh`:**
  - um Postgres `17.11-alpine` temporário, a mesma versão da simulação;
  - correção ao plano: `POSTGRES_DB=daciaramella`, e não `daciaramella_test`;
  - a imagem descarrega-se em silêncio se faltar;
  - recusa se já houver um contentor de testes;
  - o `trap` apaga o contentor também com Ctrl+C.
- **Provas:**
  - com um comando que falha, sai com erro e não deixa contentor;
  - um teste filtrado (`comandas.test.ts`, 65 testes) passa;
  - o `npm test` completo passa em 65 s: servidor 871, web 159 e ferramentas 3;
  - em todos os casos, não sobrou nenhum contentor.
- **`CLAUDE.md`:**
  - a app não corre no Mac;
  - os testes correm com o `ops/testar.sh`;
  - saem o `docker compose up`, os `db:migrate` e `db:seed` locais e a secção "Passos para aplicar mudanças (produção)";
  - entra a secção "Imagens e deploy" (`construir.sh --test` e `--release`);
  - entra a regra das migrações (D6);
  - o "Hoje" diz que a simulação parou.
  - Saíram também o `npm run dev:server` e o `dev:web`, que põem a app a correr no Mac (decisão do dono, 23/10). A nota do interruptor da faturação ficou numa linha à parte.

**23/10, passos 3 e 4 (agente, no repositório da infra):**
- **`infra/scripts/construir.sh`**, em bash, por causa do `pipefail`:
  - a cópia limpa faz-se com `git worktree` numa pasta do `$TMPDIR`, apagada pelo `trap`;
  - os testes correm com `npm ci` e o `ops/testar.sh` da cópia;
  - as imagens levam as *labels* `revision`, `version` e `created`;
  - o `docker save` usa `--platform linux/amd64`, porque o Docker do Mac (29.7.2) usa o armazenamento do *containerd*;
  - o ficheiro escreve-se como `.parcial` e só fica com o nome final no fim.
  - **Recusas provadas:**
    - sem argumentos, mostra o uso;
    - com uma *tag* inexistente (`v9.9.9`), recusa;
    - com a `v0.0.0` e com o `dev` em `a358cf0`, recusa, porque não têm o `ops/testar.sh`.
  - Em todos os casos, a pasta da app ficou como estava, sem *worktrees* a mais.
- **`infra/scripts/imagens-base.sh`:**
  - o Postgres 17.11 e o Caddy 2.11.7 ficam fixados pelo digest do índice (`imagetools inspect`);
  - o `base-2026-10-23.tar.zst` (145 MB, `.sha256` OK) demorou 27 s;
  - dentro do ficheiro, as duas imagens são `linux/amd64` (confirmado no `config` de cada uma);
  - o `postgres_imagem` e o `caddy_imagem` estão no `vars.yml`, com os digests completos em comentário.

**23/10, passo 6.1 (primeiro `--test`, autorizado pelo dono):**
- O dono commitou `0a0fc7c` no `dev`.
- **`construir.sh --test` → `daciaramella-dev-2026-10-23-1436.tar.zst` (109 MB), em 1 min 39 s no total, com os testes.** O risco do build lento (mais de 15 min) não se confirmou.
- **Aceitação:**
  - o `sha256` está OK;
  - a `app` e a `backup` são `linux/amd64`, com `revision` = `0a0fc7c8ee73…` e `version` = a etiqueta;
  - `NODE_VERSION=26.7.0`;
  - não há código-fonte: zero ficheiros em `apps/server/src` e `apps/web/src`, zero `.ts` fora do `node_modules`. Estão lá o `dist` do servidor (57 ficheiros), as migrações (31) e o `dist` da web (17);
  - a `app` tem 327 MB e a `backup` 38 MB;
  - a pasta da app ficou igual, sem *worktrees* a mais.
- **Teste partido:** num clone descartável com um commit no `dev` com um teste que falha de propósito (`APP_DIR` apontado para o clone), o script saiu com 1, sem ficheiro e sem imagens, e apagou a cópia. O clone foi apagado.
- **Ficheiros por commitar não entram:** isto vale por construção, porque a cópia sai do commit (`git worktree add <commit>`) e nunca da pasta de trabalho.
- O primeiro `--release` está no passo 6.2, abaixo.

**23/10, passo 6.2 (primeiro `--release`, autorizado pelo dono):**
- O dono fez o *pull request* #100 (`dev` → `main`, *merge* `eeaf02e`) e a Release `v0.1.0` no GitHub. A `v0.0.0` (`a358cf0`) fica como estava: é anterior ao P4 e o script recusa-a.
- **`construir.sh --release v0.1.0` → `daciaramella-v0.1.0.tar.zst` (109 MB), em 1 min 8 s, com os testes** (871, 159 e 3).
- **Aceitação:**
  - o `sha256` está OK;
  - a `app` e a `backup` são `linux/amd64`, com `revision` = `eeaf02e27ce0…` e `version` = `v0.1.0`;
  - `NODE_VERSION=26.7.0`;
  - não há código-fonte.
- O `app_tag` no `vars.yml` continua vazio até ao P6 (D10).
