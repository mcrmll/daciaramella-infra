#!/bin/bash
# Constrói as imagens da app (app e backup) para o servidor (linux/amd64) e guarda-as num ficheiro
# pronto a enviar (P4 da fase 1). Todo o contacto com a internet do build é do Mac (D1); o servidor
# nunca recebe o código (D2).
#
#   construir.sh --test              último commit do ramo dev local → etiqueta dev-AAAA-MM-DD-HHMM
#   construir.sh --release v0.1.0    tag da main do GitHub          → etiqueta v0.1.0
#
# Nunca usa a pasta de trabalho da app: tira uma cópia limpa do commit escolhido, corre os testes
# (o ops/testar.sh dessa cópia), constrói e apaga a cópia. O que não estiver commitado não entra.
#
# Variáveis: APP_DIR (o repositório da app) e RELEASE_DIR (onde fica o ficheiro).
set -euo pipefail

APP_DIR=${APP_DIR:-$HOME/business/da_ciaramella/system/daciaramella-system}
RELEASE_DIR=${RELEASE_DIR:-$HOME/daciaramella-releases}

uso() { echo "Uso: $0 --test | --release <tag>" >&2; exit 2; }
falha() { echo "construir.sh: $*" >&2; exit 1; }

[ "$#" -ge 1 ] || uso
case "$1" in
  --test)
    [ "$#" -eq 1 ] || uso
    MODO=test
    COMMIT=$(git -C "$APP_DIR" rev-parse --verify -q 'refs/heads/dev^{commit}') \
      || falha "não há ramo dev em $APP_DIR"
    TAG=dev-$(date +%Y-%m-%d-%H%M)
    ;;
  --release)
    [ "$#" -eq 2 ] || uso
    MODO=release
    TAG=$2
    echo "A buscar a main e as tags ao GitHub…"
    git -C "$APP_DIR" fetch --quiet --tags origin main
    COMMIT=$(git -C "$APP_DIR" rev-parse --verify -q "refs/tags/$TAG^{commit}") \
      || falha "a tag $TAG não existe"
    git -C "$APP_DIR" merge-base --is-ancestor "$COMMIT" refs/remotes/origin/main \
      || falha "a tag $TAG não está na main do GitHub"
    ;;
  *) uso ;;
esac

# Uma etiqueta do Docker só aceita letras, algarismos, _ . e -, até 128 caracteres.
[[ "$TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || falha "a etiqueta '$TAG' não serve para o Docker"

mkdir -p "$RELEASE_DIR"
FICHEIRO="$RELEASE_DIR/daciaramella-$TAG.tar.zst"
[ ! -e "$FICHEIRO" ] || falha "já existe $FICHEIRO"

BASE=$(mktemp -d "${TMPDIR:-/tmp}/daciaramella-construir.XXXXXX")
COPIA="$BASE/app"
limpar() {
  git -C "$APP_DIR" worktree remove --force "$COPIA" >/dev/null 2>&1 || true
  git -C "$APP_DIR" worktree prune
  rm -rf "$BASE"
  rm -f "$FICHEIRO.parcial"
}
trap limpar EXIT
trap 'exit 130' INT TERM

INICIO=$(date +%s)
echo "Modo $MODO · etiqueta $TAG · commit $COMMIT"

git -C "$APP_DIR" worktree add --detach --quiet "$COPIA" "$COMMIT"
[ -x "$COPIA/ops/testar.sh" ] \
  || falha "o commit ${COMMIT:0:7} não tem o ops/testar.sh (é anterior ao P4): faz um commit ou uma tag nova"

echo
echo "━━━ Testes ━━━"
(cd "$COPIA" && npm ci --no-audit --no-fund --loglevel=error && ops/testar.sh)

echo
echo "━━━ Imagens (linux/amd64) ━━━"
for alvo in app backup; do
  if [ "$alvo" = app ]; then dockerfile="$COPIA/Dockerfile"; else dockerfile="$COPIA/ops/backup/Dockerfile"; fi
  docker buildx build --platform linux/amd64 --load \
    --label org.opencontainers.image.revision="$COMMIT" \
    --label org.opencontainers.image.version="$TAG" \
    --label org.opencontainers.image.created="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -f "$dockerfile" -t "daciaramella/$alvo:$TAG" "$COPIA"
done

echo
echo "━━━ Ficheiro ━━━"
docker save --platform linux/amd64 "daciaramella/app:$TAG" "daciaramella/backup:$TAG" \
  | zstd -q -T0 -o "$FICHEIRO.parcial"
mv "$FICHEIRO.parcial" "$FICHEIRO"
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$FICHEIRO")" > "$(basename "$FICHEIRO").sha256")

DURACAO=$(($(date +%s) - INICIO))
echo
echo "Pronto: $FICHEIRO ($(du -h "$FICHEIRO" | cut -f1 | tr -d ' '))"
echo "  modo $MODO · etiqueta $TAG · commit $COMMIT · $((DURACAO / 60)) min $((DURACAO % 60)) s"
if [ "$MODO" = test ]; then
  echo "  deploy de teste: -e app_tag=$TAG (não fica no vars.yml)"
else
  echo "  deploy: app_tag: $TAG no vars.yml (D10)"
fi
