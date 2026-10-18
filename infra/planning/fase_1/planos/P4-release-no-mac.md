# P4 — Release no Mac

Estado: por fazer · Depende de: — · Bloqueia: P5, P6 · Executa: agente (repositórios da app e da infra); o dono autoriza os builds · Máquinas: Mac mini

## Objetivo

- **Todo o contacto com a internet do build é do Mac (D1).** Um comando produz, a partir de um commit, um ficheiro com as imagens x86 prontas a enviar.
- **O servidor nunca recebe o código (D2).** As imagens levam só o que é preciso para correr.
- **As imagens de terceiros (Postgres e Caddy) seguem o mesmo caminho,** fixadas por digest (D17).

## Passos

### Passo 1 — Node fixo (agente, repositório da app)

- No `Dockerfile`, trocar `node:26-alpine` pela versão exata do dia (`node:26.X.Y-alpine`) nos dois `FROM`.
- Assim, reconstruir o mesmo commit noutro dia dá sempre o mesmo Node. O `engines` do `package.json` pode continuar `26.x`.

### Passo 2 — `ops/testar.sh` (agente, repositório da app)

O `npm test` precisa de um Postgres. Como a app não corre no Mac (D2), o script cria um Postgres temporário, só para os testes:

```sh
docker run -d --rm --name daciaramella-testes-pg \
  -e POSTGRES_USER=daciaramella -e POSTGRES_PASSWORD=testes -e POSTGRES_DB=daciaramella_test \
  -p 127.0.0.1:55432:5432 --tmpfs /var/lib/postgresql/data \
  postgres:17.X-alpine
```

1. Espera pelo `pg_isready`.
2. Corre `DATABASE_URL_TEST=postgres://daciaramella:testes@127.0.0.1:55432/daciaramella_test npm test`. Se receber outro comando, corre esse: por exemplo `ops/testar.sh npm run test:server -- -t '<padrão>'`.
3. Apaga o contentor no fim, passem ou falhem os testes (`trap … EXIT`).

- Os dados ficam em memória e desaparecem.
- A porta 55432 só escuta no próprio Mac.
- É o mesmo script para os agentes no dia a dia e para o `release.sh`.

### Passo 3 — `ops/release.sh` (agente, repositório da app)

1. Recusa se `git status --porcelain` não estiver vazio. A tag tem de corresponder exatamente ao código.
2. Corre o `ops/testar.sh`. Se falhar, para.
3. Define a tag: `TAG=$(git rev-parse --short HEAD)`.
4. Constrói as duas imagens:

   ```sh
   docker buildx build --platform linux/amd64 --load \
     --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
     -t daciaramella/app:"$TAG" .
   docker buildx build --platform linux/amd64 --load \
     --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
     -f ops/backup/Dockerfile -t daciaramella/backup:"$TAG" .
   ```

5. Guarda-as num ficheiro:

   ```sh
   docker save daciaramella/app:"$TAG" daciaramella/backup:"$TAG" \
     | zstd -T0 > "$RELEASE_DIR/daciaramella-$TAG.tar.zst"
   shasum -a 256 "$RELEASE_DIR/daciaramella-$TAG.tar.zst" > "$RELEASE_DIR/daciaramella-$TAG.tar.zst.sha256"
   ```

   O `RELEASE_DIR` é `~/daciaramella-releases` por omissão, fora dos repositórios.
6. Mostra a tag, o caminho e o tempo que o build demorou.

### Passo 4 — `infra/scripts/imagens-base.sh` (agente, repositório da infra)

Corre raramente: na primeira instalação e quando se atualiza o Postgres ou o Caddy.

1. Para cada imagem (`postgres:17.X-alpine` e `caddy:2.X-alpine`), faz `docker pull --platform linux/amd64` pelo digest.
2. Dá-lhe uma tag local: `daciaramella/postgres:17.X-<digest curto>` e `daciaramella/caddy:2.X-<digest curto>`.
3. Guarda as duas em `~/daciaramella-releases/base-<data>.tar.zst`, com o `.sha256`.
4. Os digests e as tags locais ficam no `vars.yml` (`postgres_imagem`, `caddy_imagem`), para estarem versionados.

### Passo 5 — documentação na app (agente, repositório da app)

O `CLAUDE.md` passa a dizer:
- **a app não corre no Mac (D2).** Saem os comandos que a põem a correr localmente (`docker compose up -d --build` e os `npm run db:*` contra uma base de dados local);
- **os testes correm com `ops/testar.sh`;**
- **a regra das migrações como boa prática (D6);**
- **as releases fazem-se com `ops/release.sh`,** e o deploy faz-se no repositório da infra.

Os outros documentos da app que assumem a app a correr no Mac ficam para depois ([ESTADO](../ESTADO.md), "Fora desta fase").

### Passo 6 — primeira release (o dono autoriza; o agente corre)

Correr a partir de `main` e anotar no [ESTADO](../ESTADO.md) a tag e o tempo do build.

## Aceitação

- **`testar.sh`:**
  - no fim não sobra o contentor, passem ou falhem os testes (`docker ps -a --filter name=daciaramella-testes-pg` sai vazio);
  - com um filtro, corre só esses testes.
- **`release.sh` recusa:**
  - com a árvore suja, não constrói nada;
  - num ramo descartável com um teste partido, não constrói nada.
- **`release.sh` em `main`:**
  - produz o `.tar.zst` e o `.sha256`;
  - `docker image inspect daciaramella/app:$TAG --format '{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}'` mostra `amd64 <commit completo>`;
  - o `NODE_VERSION` em `docker image inspect daciaramella/app:$TAG --format '{{.Config.Env}}'` é a versão fixada no passo 1.
- **A imagem não leva o código-fonte:** num contentor criado sem arrancar (`docker create`), o `docker export … | tar -t` não tem `apps/server/src` nem `apps/web/src`.
- **Imagens de base:** o `imagens-base.sh` produz o ficheiro com o Postgres e o Caddy em amd64, com as tags locais.

## Riscos

- **O build é emulado e mais lento.** Se passar dos 15 minutos, rever a D1.
- **Os testes correm em arm64 no Mac e a produção em amd64.** Numa app em JavaScript sem dependências nativas, as diferenças são raras. O ensaio a sério é no servidor ([P6](P6-primeira-instalacao.md)).
- **Um ficheiro de release é grande** (centenas de MB descomprimido). O `zstd` reduz bastante. Os ficheiros antigos no Mac apagam-se à mão.
