# Guia de deploy da app (Figaro)

Como pôr uma versão nova da app no servidor, como testar uma versão do `dev`, o que verificar depois, e o que fazer quando alguma coisa corre mal.

Escrito a 23/10/2026, no fim da fase 1 da infra ([ESTADO](../../infra/planning/fase_1/ESTADO.md)).

**Regra deste guia:** cada alteração a um playbook atualiza este guia no mesmo commit.

---

## Antes de começar

- **Máquina:** o Mac mini. O Ansible, o Vault e os ficheiros das imagens estão lá.
- **Rede:** o Mac mini ligado por cabo ao router da loja. O servidor (`10.77.0.10`) só existe nessa rede.
- **Terminal:** a app Terminal do macOS.
- **Pasta dos comandos do Ansible:** `~/business/da_ciaramella/infra/daciaramella-infra/ansible`. O Ansible só lê o `ansible.cfg` da pasta onde estás.

```sh
cd ~/business/da_ciaramella/infra/daciaramella-infra/ansible
```

Os comandos `ansible-playbook` abrem o Vault sozinhos, com a password do Porta-chaves. Nunca mostram segredos no ecrã.

---

## Quando fazer um deploy

| Onde | Quando |
|---|---|
| **Servidor de testes, na bancada** (`janela_ativa: false` no `vars.yml`) | A qualquer hora. |
| **Loja** (`janela_ativa: true`) | **À segunda de manhã** (D7), com a terça de reserva, para haver dois dias de loja fechada para validar. O `deploy.yml` só aceita das 01:00 às 06:00 e à segunda e à terça o dia todo. |

- **Nunca entre as 04:15 e as 04:45:** é a hora do backup, e o `deploy.yml` recusa.
- **Fora da janela**, só com um motivo. Acrescenta `-e fora_da_janela=sim` e escreve o motivo no commit.

---

## No dia a dia, antes de uma versão

- **A app não corre no Mac** (D2). No Mac só correm os testes, com um Postgres temporário. No repositório da app:

  ```sh
  ops/testar.sh                                        # todos os testes
  ops/testar.sh npm run test:server -- src/dominio/comandas.test.ts -t 'padrão'   # só alguns
  ```

- **Para ver a app a funcionar**, põe uma versão de teste no servidor (secção "Testar uma versão do dev", abaixo).

---

## Um deploy de uma versão nova, passo a passo

### 1. A versão no GitHub

1. Junta o `dev` à `main` com um *pull request* no GitHub.
2. Cria a *tag* da versão no último commit da `main`: no GitHub, **Releases → Draft a new release → Choose a tag → `v0.2.0` → Target: `main` → Publish**. Ou, no repositório da app:

   ```sh
   gh release create v0.2.0 --target main --title "v0.2.0" --notes "O que mudou."
   ```

### 2. Construir as imagens

No repositório da infra:

```sh
cd ~/business/da_ciaramella/infra/daciaramella-infra
infra/scripts/construir.sh --release v0.2.0
```

1. Vai buscar a *tag* ao GitHub e recusa se ela não estiver na `main`.
2. Tira uma cópia limpa, sem tocar na tua pasta da app.
3. Corre os testes. **Se algum falhar, para, e não constrói nada.**
4. Constrói as imagens para o servidor (Intel) e deixa-as em `~/daciaramella-releases/daciaramella-v0.2.0.tar.zst`.

Demora 1 a 2 minutos. No fim mostra:

```text
Pronto: …/daciaramella-v0.2.0.tar.zst (109M)
  modo release · etiqueta v0.2.0 · commit … · 1 min 8 s
  deploy: app_tag: v0.2.0 no vars.yml (D10)
```

### 3. Escolher a versão no `vars.yml`

Em `ansible/inventario/group_vars/loja/vars.yml`:

```yaml
app_tag: v0.2.0
```

### 4. Ver o que vai acontecer, sem mudar nada

```sh
cd ~/business/da_ciaramella/infra/daciaramella-infra/ansible
ansible-playbook playbooks/deploy.yml --check --diff
```

- No início, a tarefa **"O que vai acontecer"** diz o caso. Para uma versão nova: `Troca: v0.1.0 → v0.2.0`.
- O `--diff` mostra o que muda no `compose.yml` e no `Caddyfile`. Os segredos nunca aparecem.
- No fim tem de dizer `failed=0`.

### 5. O deploy

```sh
ansible-playbook playbooks/deploy.yml
```

O que ele faz, por ordem:

1. **Verificações, que não mexem em nada:**
   - a validação da configuração;
   - a janela (só na loja);
   - a versão atual está saudável;
   - há 5 GB livres;
   - a versão pedida existe.
2. **As imagens:** envia-as para o servidor, só as que faltarem.
3. **O backup cifrado normal**, enviado para a R2.
4. **O pacote atual** (`compose.yml`, `.env`, `Caddyfile`, `rclone.conf`) fica guardado em `anterior/`.
5. **A cópia da base de dados:** para a app uns segundos e copia a base de dados para `rollback_<versão atual>`.
6. **A troca:** arranca a versão nova e espera que fique `healthy` e responda por HTTPS.

Demora cerca de 1 minuto. **Correu bem** quando acaba com:

```text
"Troca feita: v0.1.0 → v0.2.0. A cópia rollback_v0.1.0 fica até ao próximo deploy. Fazer agora a lista de verificação (P9)."
… failed=0
```

**Se a versão nova falhar ao arrancar, volta sozinho** à versão anterior, com a base de dados e a configuração de antes, e termina com erro:

```text
"O deploy de v0.2.0 falhou em «…» e voltou sozinho para a v0.1.0, com a BD e a configuração de antes. …
 Logs da app: ~/daciaramella-releases/logs/deploy-….log"
```

Nesse caso, vê "Se alguma coisa correr mal", mais abaixo.

### 6. A lista de verificação (cerca de 5 minutos)

Na secção seguinte.

### 7. O commit

**Só se o deploy e a lista correram bem** (D10). No repositório da infra:

```sh
git add ansible/inventario/group_vars/loja/vars.yml
git commit -m "Deploy v0.2.0"
```

Se o deploy falhou e voltou sozinho, **repõe o `app_tag` antigo** no `vars.yml` e não commites.

---

## A lista de verificação, depois de cada deploy

No PC do balcão. Na bancada, é o Mac mini a fazer de balcão.

1. Abre `https://app.figaro.local`. Tem de abrir **sem aviso de certificado**.
2. Entra na **Gestão** (`/management/login`).
3. No **balcão**, cria uma comanda em modo teste e vê-a aparecer na **cozinha**, em tempo real.
4. **Imprime o talão.**
5. Em **Sistema → Moloni**, confirma que a ligação está viva.
6. No Terminal, na pasta `ansible/`:

   ```sh
   ansible loja -b -a 'tail -3 /opt/daciaramella/deploys.log'
   ansible loja -b -a 'docker compose -f /opt/daciaramella/compose.yml exec -T backup cat /backups/ultimo-backup.json'
   ```

   A última linha do `deploys.log` tem de ser a do teu deploy (`troca … ok`), e o último backup tem de dizer `"upload":"ok"`.

**Se algum ponto falhar**, ainda na mesma noite e antes de a loja abrir, usa o `repor-copia.yml` (abaixo).

---

## Testar uma versão do `dev` no servidor

Para ver uma mudança a funcionar antes de a juntar à `main`. Só no servidor de testes.

1. Faz o commit no `dev` da app. O que não estiver commitado não entra.
2. Constrói:

   ```sh
   cd ~/business/da_ciaramella/infra/daciaramella-infra
   infra/scripts/construir.sh --test
   ```

   A etiqueta é a data e a hora, por exemplo `dev-2026-10-23-1638`.
3. Faz o deploy **sem mexer no `vars.yml`**:

   ```sh
   cd ansible
   ansible-playbook playbooks/deploy.yml -e app_tag=dev-2026-10-23-1638
   ```

   O `-e` (*extra vars*) passa a versão só para este comando.
4. Para voltar à versão oficial, a do `vars.yml`, corre o deploy sem `-e`:

   ```sh
   ansible-playbook playbooks/deploy.yml
   ```

Os dois deploys são trocas normais, com a cópia da base de dados e a reposição automática.

---

## O que o `deploy.yml` pode responder

| Mensagem em "O que vai acontecer" | O que quer dizer |
|---|---|
| `Instalação da v…` | Ainda não havia app no servidor. Instala, sem cópia (não há nada para guardar). |
| `Troca: v… → v…` | Outra versão, ou a mesma com outra configuração. Faz a cópia da base de dados e a troca. |
| `Nada a fazer: o servidor já está na v…` | Já está tudo como pedido. Não para a app nem faz cópia. |
| `Reparar a v…` | A mesma versão, mas falta uma imagem ou um serviço está parado. Envia o que faltar e volta a arrancar, sem cópia da base de dados. |

E quando recusa sem mexer em nada:

| Mensagem | O que fazer |
|---|---|
| `Fora da janela de manutenção` | Esperar pela janela, ou `-e fora_da_janela=sim`, com um motivo. |
| `Entre as 04:15 e as 04:45 corre o backup` | Esperar uns minutos. |
| `A versão atual (…) não está saudável` | Ver primeiro porquê (logs, "Comandos de consulta"). Para avançar mesmo assim: `-e forcar=sim`. |
| `Só há … GB livres` | Libertar espaço no servidor antes do deploy. |
| `As imagens … não estão no servidor, e falta daciaramella-….tar.zst` | Correr primeiro o `construir.sh` dessa versão. |

---

## Se alguma coisa correr mal

| Situação | O que fazer |
|---|---|
| **O `construir.sh` falhou nos testes** | Corrigir no `dev`, juntar à `main` e fazer uma *tag* nova. Para repetir só esses testes: `ops/testar.sh npm run test:server -- <ficheiro> -t '<padrão>'`. |
| **O deploy falhou e voltou sozinho** | O servidor está na versão anterior, com os dados de antes. Ler o log em `~/daciaramella-releases/logs/`, corrigir e fazer outra versão. Repor o `app_tag` antigo no `vars.yml`. A base de dados da tentativa ficou como `falhado_<versão>`; o deploy seguinte avisa que ela existe. |
| **O deploy falhou e a versão anterior também não arranca** | O playbook para e mostra o estado dos contentores e das bases de dados. **Não corras mais nada às cegas.** Vê "Recuperar à mão", abaixo. |
| **Um problema descoberto na mesma noite, antes de a loja abrir** | `ansible-playbook playbooks/repor-copia.yml`: volta à versão anterior **e aos dados de antes do deploy**. |
| **Um problema descoberto depois de a loja abrir** | **Não reponhas a cópia: apagaria as vendas do dia.** Ou corriges e fazes uma versão nova, ou fazes o deploy da versão anterior (`app_tag` anterior no `vars.yml`, e `deploy.yml`). Isso troca só a imagem e mantém os dados. |
| **Faturas erradas ou a mais** | Pausar a emissão (abaixo) e depois investigar. As vendas continuam e as faturas ficam em fila. |
| **A app não abre no browser** | `ansible-playbook playbooks/deploy.yml`. Se faltar alguma coisa ou um serviço estiver parado, ele diz `Reparar` e trata disso. |
| **O servidor reiniciou** (por exemplo, um corte de luz) | Tudo volta sozinho em menos de um minuto. Se não voltar, `deploy.yml` (repara). |

### Repor a cópia (só na noite do deploy)

```sh
ansible-playbook playbooks/repor-copia.yml
```

1. Mostra a versão atual, a versão para onde volta, a hora da cópia e as comandas em cada lado.
2. **Recusa se houver comandas novas desde o deploy:** a loja já trabalhou, e repor apagaria essas vendas.
3. Pede-te que escrevas `sim`.
4. Volta à versão anterior com a cópia. A base de dados da versão nova fica como `substituido_<versão>`.
5. No fim, lembra-te de repor o `app_tag` anterior no `vars.yml` e de commitar.

A cópia só existe depois de um deploy que correu bem, e até ao deploy seguinte. Depois de um deploy que falhou e voltou sozinho, já não há cópia.

### Pausar ou retomar a emissão de faturas (a qualquer hora)

1. No `vars.yml`: `faturacao_emissao_ativa: 0` (para pausar) ou `1` (para retomar).
2. No Terminal:

   ```sh
   ansible-playbook playbooks/faturacao.yml
   ```

   Recria só a app, com cerca de 10 segundos sem serviço. Pode correr com a loja aberta.
3. Faz o commit do `vars.yml`, para o próximo deploy não voltar a ligar a emissão por engano.

### Recuperar à mão (quando nem a versão anterior arranca)

O playbook mostrou a lista de bases de dados. Os nomes dizem o que cada uma é:

| Base de dados | O que é |
|---|---|
| `daciaramella` | a que a app usa |
| `rollback_<versão>` | a cópia feita antes do deploy, com os dados de antes |
| `falhado_<versão>` | a da tentativa que falhou |
| `substituido_<versão>` | a que o `repor-copia.yml` tirou de uso |

1. Liga-te ao servidor e vê o estado:

   ```sh
   ssh mciaramella@10.77.0.10
   cd /opt/daciaramella
   sudo docker compose ps -a
   sudo docker compose logs --tail 100 app
   ```

2. Se a app não arranca por causa da base de dados, há o backup cifrado da noite: na R2, em `teste_loja/` (ou `loja/`), e no volume `daciaramella_backups`. **Para restaurar é precisa a chave privada `age`, que não está no servidor.** O procedimento está no `docs/backup-restauro.md` da app.
3. Antes de mexer em bases de dados à mão, para e pede ajuda. Uma reposição mal feita pode apagar dados.

---

## Comandos de consulta (não mudam nada)

Na pasta `ansible/`:

```sh
# Os contentores e o estado deles
ansible loja -b -a 'docker compose -f /opt/daciaramella/compose.yml ps'

# As últimas linhas do registo dos deploys
ansible loja -b -a 'tail -5 /opt/daciaramella/deploys.log'

# O último backup
ansible loja -b -a 'docker compose -f /opt/daciaramella/compose.yml exec -T backup cat /backups/ultimo-backup.json'

# As bases de dados que existem
ansible loja -b -a 'docker compose -f /opt/daciaramella/compose.yml exec -T postgres psql -U daciaramella -d postgres -c "\l"'

# A app responde? (no Mac mini, com o /etc/hosts da bancada)
curl https://app.figaro.local/health
```

O `/health` tem de responder `{"ok":true,"db":true}`.

---

## Onde está cada coisa

| Onde | O quê |
|---|---|
| **Servidor**, `/opt/daciaramella/` | `compose.yml`, `.env` (segredos, 0600), `Caddyfile`, `rclone/rclone.conf` (segredos, 0600), `anterior/` (o pacote da versão anterior), `caddy/` (inclui a raiz do HTTPS) e `deploys.log`. A pasta `releases/` só tem ficheiros durante um deploy. **O servidor nunca tem o código da app.** |
| **Mac mini**, `~/daciaramella-releases/` | os ficheiros das imagens de cada versão (`daciaramella-<versão>.tar.zst` e `.sha256`), as imagens de base (`base-<data>.tar.zst`), o certificado público do HTTPS (`caddy-raiz.crt`) e os logs dos deploys que falharam (`logs/`). Os ficheiros antigos podem apagar-se à mão: o servidor guarda as 3 últimas versões. |
| **Repositório da infra** (Git) | os playbooks (`ansible/playbooks/`), os modelos (`ansible/modelos/`), o `vars.yml` com a versão em produção, e o Vault cifrado (`vault.yml` e `vault_caddy.yml`). |
| **Segredos** | no Vault (cifrado no Git). A password do Vault está no Porta-chaves do Mac mini e no cofre de passwords pessoal. |
| **Backups** | todas as noites às 04:30 e antes de cada deploy: cifrados com a chave pública `age`, no volume do servidor e na R2 (`teste_loja/` na bancada, `loja/` na loja). |

---

## Os playbooks, de relance

| Comando | Para quê |
|---|---|
| `ansible-playbook playbooks/base.yml` | A base do servidor: SSH, firewall, Docker, fuso e pastas. Raramente. |
| `ansible-playbook playbooks/deploy.yml` | Instalar, trocar de versão ou reparar. |
| `ansible-playbook playbooks/repor-copia.yml` | Voltar atrás com os dados, na noite do deploy. |
| `ansible-playbook playbooks/faturacao.yml` | Pausar ou retomar a emissão de faturas. |
| `infra/scripts/construir.sh --release <tag>` ou `--test` | Construir as imagens da app (no Mac). |
| `infra/scripts/imagens-base.sh` | Trazer o Postgres e o Caddy (raramente, quando se atualizam). |
| `infra/scripts/guardar-raiz-caddy.sh` | Guardar a raiz do HTTPS no Vault (uma vez, depois da primeira instalação). |

Qualquer `ansible-playbook` aceita `--check --diff` para ver o que faria sem mudar nada.

---

## Quando o servidor for para a loja

1. No `vars.yml`: `janela_ativa: true` e `rclone_remote: r2:daciaramella-backups/loja`. Depois, `deploy.yml`: é uma troca de configuração, com cópia.
2. No Mac mini, apagar a linha da bancada do `/etc/hosts`:

   ```sh
   sudo sed -i '' '/app\.figaro\.local/d' /etc/hosts
   ```

3. Nos PCs Windows da loja, instalar o `caddy-raiz.crt` como autoridade de confiança. Isto fica para outra fase.
