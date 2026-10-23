#!/bin/bash
# Descarrega no Mac as imagens de terceiros (Postgres e Caddy) para linux/amd64, fixadas pelo digest,
# e guarda-as num ficheiro pronto a enviar (P4 da fase 1). O servidor nunca descarrega imagens (D17).
#
# Corre raramente: na primeira instalação e quando se atualiza o Postgres ou o Caddy (mudar as
# versões abaixo). No fim mostra as linhas postgres_imagem e caddy_imagem para o vars.yml.
#
# Variável: RELEASE_DIR (onde fica o ficheiro).
set -euo pipefail

POSTGRES_VERSAO=17.11 # a mesma do ops/testar.sh da app
CADDY_VERSAO=2.11.7

RELEASE_DIR=${RELEASE_DIR:-$HOME/daciaramella-releases}
mkdir -p "$RELEASE_DIR"
FICHEIRO="$RELEASE_DIR/base-$(date +%Y-%m-%d).tar.zst"
[ ! -e "$FICHEIRO" ] || { echo "imagens-base.sh: já existe $FICHEIRO" >&2; exit 1; }
trap 'rm -f "$FICHEIRO.parcial"' EXIT

# Fixa uma imagem pelo digest e dá-lhe uma etiqueta local daciaramella/<nome>:<versão>-<digest curto>.
# Escreve a etiqueta local no stdout.
fixar() {
  local nome=$1 versao=$2 origem digest local
  origem="$nome:$versao-alpine"
  digest=$(docker buildx imagetools inspect "$origem" --format '{{.Manifest.Digest}}')
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "imagens-base.sh: não encontrei o digest de $origem" >&2; exit 1; }
  docker pull --quiet --platform linux/amd64 "$nome@$digest" >/dev/null
  local="daciaramella/$nome:$versao-${digest:7:12}"
  docker tag "$nome@$digest" "$local"
  echo "  $origem → $digest" >&2
  echo "$local"
}

echo "━━━ Imagens de base (linux/amd64) ━━━" >&2
POSTGRES=$(fixar postgres "$POSTGRES_VERSAO")
CADDY=$(fixar caddy "$CADDY_VERSAO")

docker save --platform linux/amd64 "$POSTGRES" "$CADDY" | zstd -q -T0 -o "$FICHEIRO.parcial"
mv "$FICHEIRO.parcial" "$FICHEIRO"
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$FICHEIRO")" > "$(basename "$FICHEIRO").sha256")

echo
echo "Pronto: $FICHEIRO ($(du -h "$FICHEIRO" | cut -f1 | tr -d ' '))"
echo "Para o vars.yml:"
echo "  imagens_base_ficheiro: $(basename "$FICHEIRO")"
echo "  postgres_imagem: $POSTGRES"
echo "  caddy_imagem: $CADDY"
