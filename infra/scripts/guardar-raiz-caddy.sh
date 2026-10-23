#!/bin/bash
# Guarda no Vault a raiz da CA interna do Caddy do servidor (P6, passo 3).
#
# Corre-o o dono, no Terminal do Mac mini. O agente não o corre: a chave privada da raiz é um segredo.
# Corre-se uma vez, depois da primeira instalação. Numa reinstalação, o deploy.yml repõe esta raiz antes
# de o Caddy arrancar, e os postos da loja continuam a confiar no HTTPS sem instalar nada outra vez.
#
# 1. Vai buscar o root.crt e o root.key ao servidor (Ansible, módulo fetch) para uma pasta temporária.
# 2. Escreve-os cifrados em ansible/inventario/group_vars/loja/vault_caddy.yml (vault_caddy_root_crt e _key).
# 3. Apaga a pasta temporária: a chave não fica em claro no disco.
# 4. Deixa o certificado público em ~/daciaramella-releases/caddy-raiz.crt, para confiar nele no Mac mini.
set -euo pipefail

ANSIBLE_DIR=$(cd "$(dirname "$0")/../../ansible" && pwd)
DESTINO="$ANSIBLE_DIR/inventario/group_vars/loja/vault_caddy.yml"
RAIZ_NO_SERVIDOR=/opt/daciaramella/caddy/data/caddy/pki/authorities/local
RELEASE_DIR=${RELEASE_DIR:-$HOME/daciaramella-releases}

if [ -e "$DESTINO" ]; then
  echo "Já existe $DESTINO. Para guardar outra raiz, apagar esse ficheiro primeiro, de propósito." >&2
  exit 1
fi

TMP=$(mktemp -d)
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

cd "$ANSIBLE_DIR"
echo "A buscar a raiz ao servidor…"
for f in root.crt root.key; do
  ansible loja -b -m ansible.builtin.fetch -a "src=$RAIZ_NO_SERVIDOR/$f dest=$TMP/$f flat=true" >/dev/null
done

# Confirma que é mesmo a raiz do Caddy, e que a chave corresponde ao certificado.
openssl x509 -in "$TMP/root.crt" -noout -subject
[ "$(openssl x509 -in "$TMP/root.crt" -noout -pubkey)" = "$(openssl pkey -in "$TMP/root.key" -pubout)" ] \
  || { echo "A chave não corresponde ao certificado." >&2; exit 1; }

{
  echo "# Raiz da CA interna do Caddy do servidor (P6). Escrito pelo infra/scripts/guardar-raiz-caddy.sh."
  echo "vault_caddy_root_crt: |"
  sed 's/^/  /' "$TMP/root.crt"
  echo "vault_caddy_root_key: |"
  sed 's/^/  /' "$TMP/root.key"
} > "$TMP/vault_caddy.yml"
ansible-vault encrypt --output "$DESTINO" "$TMP/vault_caddy.yml" >/dev/null

mkdir -p "$RELEASE_DIR"
cp "$TMP/root.crt" "$RELEASE_DIR/caddy-raiz.crt"

echo
echo "Guardado (cifrado): $DESTINO"
echo "  $(head -1 "$DESTINO")"
echo "Certificado público para o Mac mini: $RELEASE_DIR/caddy-raiz.crt"
echo "  $(openssl x509 -in "$RELEASE_DIR/caddy-raiz.crt" -noout -fingerprint -sha256)"
