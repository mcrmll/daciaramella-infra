# P6 — Primeira instalação no servidor de testes

Estado: em curso (passos 1 e 2 feitos a 23/10 pelo agente, a pedido do dono; faltam os passos do dono: 3, 4, 5 e o backup do dia seguinte) · Depende de: P3, P4, P5 · Bloqueia: P7 · Executa: agente e dono (cada passo diz quem) · Máquinas: Mac mini → servidor

## Objetivo

A app a correr no servidor por HTTPS, com o nome do [P3](P3-nome-local.md), instalada só pelo Ansible, a partir de uma base limpa (D5). O servidor recebe só imagens e configuração (D2). A raiz do Caddy fica guardada no Vault, para sobreviver a uma reinstalação.

## Passos

### Passo 1 — `deploy.yml`, modo de instalação (agente)

É a primeira versão do playbook. Entra em modo de instalação quando ainda não existe `/opt/daciaramella/compose.yml`. O P7 acrescenta a cópia e o rollback.

1. **Confirma o pedido:** o `app_tag` não está vazio, o ficheiro da release está em `release_dir` e o `sha256` bate certo.
2. **Envia e carrega as imagens** da release e as de base, só as que o servidor ainda não tiver (`docker image inspect`):
   - copia o ficheiro para `/opt/daciaramella/releases/`;
   - corre `zstd -dc … | docker load`;
   - **apaga o ficheiro.** O servidor fica só com as imagens carregadas.
3. **Confirma que a etiqueta `org.opencontainers.image.revision`** da imagem `app` começa pelo `app_tag`.
4. **Valida o compose** (a tarefa `validar` do P5).
5. **Escreve os ficheiros de `/opt/daciaramella/`:** `compose.yml`, `.env` (0600) e `Caddyfile`.
6. **Põe a raiz do Caddy no sítio:** se o Vault já tiver a raiz e `caddy/data/caddy/pki/authorities/local/` estiver vazio, escreve lá o `root.crt` e o `root.key` (0600) (passo 3).
7. **Arranca tudo:** `docker compose up -d`.
8. **Espera pela app:** até 2 minutos pelo estado `healthy`. Depois faz um pedido pelo Caddy:

   ```sh
   curl -fsS --resolve {{ app_nome }}:443:127.0.0.1 \
     --cacert /opt/daciaramella/caddy/data/caddy/pki/authorities/local/root.crt \
     https://{{ app_nome }}/health
   ```

9. **Regista** uma linha em `/opt/daciaramella/deploys.log`: data, `instalação` e a tag.

### Passo 2 — instalar (dono)

1. No Mac, correr o `infra/scripts/imagens-base.sh` e o `construir.sh --release <tag>` ([P4](P4-release-no-mac.md)).
2. Pôr no `vars.yml` o `app_tag` e as tags locais das imagens de base.
3. Correr `ansible-playbook playbooks/deploy.yml --check --diff`, e depois a sério.

### Passo 3 — raiz do Caddy no Vault (dono, no Terminal)

O Caddy gera a raiz no primeiro arranque. Para não ser preciso reinstalá-la nos postos depois de uma reinstalação, guarda-se no Vault:

1. Correr `infra/scripts/guardar-raiz-caddy.sh`. Mudança aprovada pelo dono a 23/10, em vez do `ssh` + `sudo cat` + `encrypt_string`: o `sudo` por SSH precisa de um terminal, que estraga os fins de linha, e colar a chave no vi é fácil de estragar. O script:
   - traz o `root.crt` e o `root.key` com o Ansible (`fetch`) para uma pasta temporária;
   - confirma que a chave corresponde ao certificado;
   - escreve-os cifrados em `group_vars/loja/vault_caddy.yml` (`vault_caddy_root_crt` e `vault_caddy_root_key`);
   - apaga a pasta temporária;
   - deixa o certificado público em `~/daciaramella-releases/caddy-raiz.crt`.
2. Instalar o `caddy-raiz.crt` no Porta-chaves do Mac mini (Sistema) e marcá-lo como "Confiar sempre" para SSL. Na bancada, o Mac mini faz de PC do balcão (Q4 do [ESTADO](../ESTADO.md)). Os PCs Windows da loja ficam para outra fase.

### Passo 4 — o Mac mini a fazer de PC do balcão (dono)

O macOS não pergunta ao router os nomes `.local` (usa o Bonjour), e o Mac mini faz as perguntas de DNS pelo Wi-Fi primeiro. Por isso, só durante a fase da bancada:

1. Acrescentar ao `/etc/hosts` do Mac mini a linha `10.77.0.10  app.figaro.local` (com `sudo`).
2. Confirmar que o registo do router também está certo, perguntando-lhe diretamente: `nslookup app.figaro.local 10.77.0.1` devolve `10.77.0.10`.
3. Quando a fase da bancada acabar, apagar a linha do `/etc/hosts`.

Os PCs da loja não precisam de nada disto: perguntam ao router.

### Passo 5 — primeira verificação (dono)

É a lista do [P9](P9-guia-e-ensaio-geral.md), na primeira versão, feita pelo dono no Mac mini a fazer de PC do balcão:

1. No Mac mini, abrir `https://app.figaro.local`, sem aviso de certificado.
2. Entrar como `admin`, com a `ADMIN_PASSWORD_INICIAL`.
3. Criar uma comanda em modo teste no balcão e vê-la aparecer na cozinha.
4. Configurar a impressora na Gestão (`10.77.0.30:9100`) e imprimir o talão.
5. Em Sistema → Moloni, entrar na conta de testes. Com a simulação do Mac mini parada (D2), o servidor é a única instalação ligada a ela.

## Aceitação

- **A instalação fez-se só com o Ansible.** No servidor, só se fizeram leituras à mão.
- **O servidor não tem o código:**
  - `/opt/daciaramella/` só tem `compose.yml`, `.env`, `Caddyfile`, `anterior/`, `caddy/`, `rclone/`, `releases/` (vazia) e `deploys.log`;
  - `find / -path /proc -prune -o -name '*.ts' -path '*apps/server/src*' -print` não encontra nada.
- **HTTPS:** `https://app.figaro.local` abre no Mac mini, a fazer de PC do balcão, sem aviso de certificado.
- **O registo do router:** `nslookup app.figaro.local 10.77.0.1` devolve `10.77.0.10`.
- **O `/health` pelo Caddy** devolve `{"ok":true,"db":true}`.
- **O talão sai na impressora,** enviado pelo servidor.
- **Portas, vistas de um Mac na bancada:** a 5432 e a 3000 do `10.77.0.10` estão fechadas e a 443 está aberta.
- **Nunca descarrega imagens:** depois de `docker image rm daciaramella/backup:<tag>`, o `docker compose up -d` falha com "image not found" e não a vai buscar. Para repor, correr outra vez o `deploy.yml`, que volta a enviar a imagem em falta.
- **Reinício:** depois de reiniciar o servidor, tudo volta sozinho e o `/health` responde.
- **Backup:**
  - no dia seguinte, o backup das 04:30 está no volume `daciaramella_backups`, com `"upload":"ok"`;
  - está também na R2, na pasta `teste_loja/` do `daciaramella-backups` (Q1). Vê-se no painel da Cloudflare.
- **Raiz:** com o Caddy parado e a pasta `caddy/data` apagada, um novo `deploy.yml` repõe a mesma raiz. A impressão digital (`openssl x509 -noout -fingerprint -sha256`) é igual à de antes.
- **Repetível:** recomeçar do zero no servidor de testes (o dono corre `docker compose down -v` e apaga `/opt/daciaramella`) e voltar a correr o `base.yml` e o `deploy.yml` deixa tudo como estava, com a mesma raiz.

## Riscos

- **A `ADMIN_PASSWORD_INICIAL` só conta no primeiro arranque** com a base de dados vazia. Depois disso, mudá-la não muda nada.
- **A conta de testes da Moloni ainda tem tokens da simulação do Mac mini.** Entrar outra vez no servidor (passo 5.5) cria tokens novos, e os antigos deixam de interessar.
- **Esquecer a linha do `/etc/hosts` no Mac mini** depois da bancada. Não estraga nada na loja, mas o Mac mini continuaria a apontar o nome para o servidor. O passo 4.3 trata disso.
- **No macOS, um nome `.local` no `/etc/hosts` às vezes demora uns segundos a resolver na primeira vez.** Não afeta o teste.

## Registo

**23/10, passos 1 e 2 (agente, a pedido do dono: "consegues fazer tudo e explicar-me?").** Os passos com segredos, com `sudo` no Mac ou com as credenciais do dono (3, 4 e 5) ficam com o dono.
- **`playbooks/deploy.yml`, modo de instalação,** mais o `playbooks/tarefas/enviar-imagens.yml`, incluído uma vez por ficheiro de imagens (`include_tasks` com `loop`).
  - **Instalar ou reaplicar:** lê o `compose.yml` instalado (`slurp`). Sem ele, instala; com a mesma versão, volta a aplicar. Com outra versão, para: isso é o P7.
  - **Imagens:** confere o ficheiro no Mac e o `sha256`. Só envia se faltar alguma imagem no servidor (`docker image inspect`), carrega com `zstd -dc | docker load` e apaga o ficheiro no `always`. Confirma que a *label* `version` da imagem é o `app_tag`.
  - **Configuração:** `compose.yml`, `Caddyfile`, `.env` (0600) e `rclone/rclone.conf` (0600). Os segredos levam `no_log` e `diff: false`.
  - **Raiz do Caddy:** se o Vault a tiver (`vault_caddy.yml`) e o servidor não, repõe-na antes de arrancar.
  - **Arranque:** `community.docker.docker_compose_v2` com `pull: never` e `wait: true`, até 180 s. Depois, `curl` ao `/health` pelo Caddy, com `--resolve` e a raiz como `--cacert`, com `until`/`retries`.
  - **`deploys.log`:** data, `instalação` ou `mesma versão`, a tag e o commit.
- **`vars.yml`:**
  - `app_tag: v0.1.0`;
  - `imagens_base_ficheiro: base-2026-10-23.tar.zst`, que o `imagens-base.sh` também passa a mostrar;
  - `release_dir` com o `HOME` por extenso, porque o `~` não é expandido em todo o lado.
- **Corrigido no bloco `validar`:** a verificação de mudanças de linha usava `"\n"`, e esta versão do Ansible não interpreta as barras invertidas nas *strings* do Jinja2, por isso não apanhava nada. Passou a `item.splitlines() | join('') == item`, testada com 4 casos. Pela mesma razão, a versão instalada lê-se com `regex_findall` e uma classe de caracteres sem `\`.
- **`--check --diff`:** `failed=0`, e nenhuma linha com segredos no registo.
- **A sério:** `ok=44 changed=19 failed=0`, em 61 s. Nenhuma linha com segredos no registo.
- **Aceitação (a parte do agente):**
  - a `app` e o `postgres` estão `healthy`, e o `backup` e o `caddy` estão `Up`;
  - o `/opt/daciaramella/` tem `.env` (600), `Caddyfile`, `compose.yml`, `deploys.log`, `anterior/`, `caddy/`, `rclone/` (700, com `rclone.conf` 600) e `releases/` vazia;
  - zero ficheiros `.ts` da app no servidor;
  - do Mac, a 5432 e a 3000 estão fechadas e a 443 está aberta;
  - `https://app.figaro.local/health` pela rede da loja responde `{"ok":true,"db":true}`;
  - o Caddy criou a raiz, em `caddy/data/caddy/pki/authorities/local/`.
- **Reaplicar a mesma versão** (idempotência): `changed=8`, todos da pasta temporária da validação e do `deploys.log`. As imagens foram saltadas, a configuração ficou `ok`, e os contentores não foram recriados (`Up 3 minutes`).
- **Falta:**
  - passo 3 (dono): `guardar-raiz-caddy.sh` e confiar na raiz no Mac mini;
  - passo 4 (dono): o `/etc/hosts`;
  - passo 5 (dono): a primeira verificação no browser;
  - o backup de amanhã na R2 (`teste_loja/`);
  - da aceitação, com autorização: o reinício, o "nunca descarrega imagens", a raiz reposta pelo Vault e o recomeçar do zero.
