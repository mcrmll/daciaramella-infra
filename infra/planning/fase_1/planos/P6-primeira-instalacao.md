# P6 — Primeira instalação no servidor de testes

Estado: por fazer · Depende de: P3, P4, P5 · Bloqueia: P7 · Executa: agente e dono (cada passo diz quem) · Máquinas: Mac mini → servidor

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

1. No Mac, correr o `infra/scripts/imagens-base.sh` e o `ops/release.sh` a partir da `main` ([P4](P4-release-no-mac.md)).
2. Pôr no `vars.yml` o `app_tag` e as tags locais das imagens de base.
3. Correr `ansible-playbook playbooks/deploy.yml --check --diff`, e depois a sério.

### Passo 3 — raiz do Caddy no Vault (dono, no Terminal)

O Caddy gera a raiz no primeiro arranque. Para não ser preciso reinstalá-la nos postos depois de uma reinstalação, guarda-se no Vault:

1. Com `ssh` e `sudo cat`, ler o `root.crt` e o `root.key` diretamente para o `ansible-vault encrypt_string --stdin-name vault_caddy_root_crt` (e `…_key`). Juntar o resultado ao `vault.yml` com `ansible-vault edit`.
2. Instalar o `root.crt` no Porta-chaves do Mac mini (Sistema) e marcá-lo como "Confiar sempre" para SSL. Na bancada, o Mac mini faz de PC do balcão (Q4 do [ESTADO](../ESTADO.md)). Os PCs Windows da loja ficam para outra fase.

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
  - `/opt/daciaramella/` só tem `compose.yml`, `.env`, `Caddyfile`, `anterior/`, `caddy/`, `releases/` (vazia) e `deploys.log`;
  - `find / -path /proc -prune -o -name '*.ts' -path '*apps/server/src*' -print` não encontra nada.
- **HTTPS:** `https://app.figaro.local` abre no Mac mini, a fazer de PC do balcão, sem aviso de certificado.
- **O registo do router:** `nslookup app.figaro.local 10.77.0.1` devolve `10.77.0.10`.
- **O `/health` pelo Caddy** devolve `{"ok":true,"db":true}`.
- **O talão sai na impressora,** enviado pelo servidor.
- **Portas, vistas de um Mac na bancada:** a 5432 e a 3000 do `10.77.0.10` estão fechadas e a 443 está aberta.
- **Nunca descarrega imagens:** depois de `docker image rm daciaramella/backup:<tag>`, o `docker compose up -d` falha com "image not found" e não a vai buscar. Para repor, correr outra vez o `deploy.yml`, que volta a enviar a imagem em falta.
- **Reinício:** depois de reiniciar o servidor, tudo volta sozinho e o `/health` responde.
- **Backup:** no dia seguinte, o backup das 04:30 está no volume `daciaramella_backups`, com `"upload":"nao_configurado"` (Q1).
- **Raiz:** com o Caddy parado e a pasta `caddy/data` apagada, um novo `deploy.yml` repõe a mesma raiz. A impressão digital (`openssl x509 -noout -fingerprint -sha256`) é igual à de antes.
- **Repetível:** recomeçar do zero no servidor de testes (o dono corre `docker compose down -v` e apaga `/opt/daciaramella`) e voltar a correr o `base.yml` e o `deploy.yml` deixa tudo como estava, com a mesma raiz.

## Riscos

- **A `ADMIN_PASSWORD_INICIAL` só conta no primeiro arranque** com a base de dados vazia. Depois disso, mudá-la não muda nada.
- **A conta de testes da Moloni ainda tem tokens da simulação do Mac mini.** Entrar outra vez no servidor (passo 5.5) cria tokens novos, e os antigos deixam de interessar.
- **Esquecer a linha do `/etc/hosts` no Mac mini** depois da bancada. Não estraga nada na loja, mas o Mac mini continuaria a apontar o nome para o servidor. O passo 4.3 trata disso.
- **No macOS, um nome `.local` no `/etc/hosts` às vezes demora uns segundos a resolver na primeira vez.** Não afeta o teste.
