# Estado da fase 1: a app no servidor de testes, com deploy e rollback

O dono pediu a 18/10 um plano em fases testáveis para instalar a app no servidor de testes (o EliteDesk da bancada) e para fazer os deploys seguintes. A estratégia de deploy foi decidida no mesmo dia. Ainda a 18/10, o dono acrescentou duas coisas:
- a app deixa de correr nos Macs: o Mac constrói e faz o deploy, e o servidor só corre a app;
- a app só se acede na rede da loja, pelo nome `app.figaro.local`. Os Macs não acedem à app.

Esta fase **não é** a "Fase 1: servidor base" do [plano geral](../../Infra%20da%20pizzaria%20contexto%20e%20plano.md). Junta o mínimo da base (Docker, fuso e nome local) ao deploy da Fase 3 do plano geral, para pôr a app a correr cedo. O proxy, a firewall nftables e o restauro a partir da R2 ficam para fases seguintes (ver "Fora desta fase").

**Estado: P1 feito a 18/10 (commit `0bea588`, só a pasta `ansible/`). P2 feito a 23/10: Docker, fuso e pastas no servidor pelo `base.yml`, e a segunda corrida deu `changed=0`. P3 em curso: falta o teste sem internet. P4 feito a 23/10: a `v0.1.0` está construída em `~/daciaramella-releases/`.**

O P1, em resumo. Os quatro passos foram feitos a 18/10:
- passo 1: a simulação parou, com `docker compose down` sem `-v`;
- passo 2: Ansible instalado (`ansible` 14.5.0, `ansible-core` 2.21.5, `community.docker` 5.4.0);
- passo 3: a estrutura `ansible/`;
- passo 4: o Vault, cifrado, com as sete variáveis do plano. O `vault_age_public_key` foi o último a entrar: o dono tirou-o do `.env` da app.

Aceitação, corrida pelo dono a 18/10:
- o `ping` respondeu `pong`, com o Python 3.14 no servidor;
- o `whoami` com `-b` respondeu `root`, com o `sudo.ws` lido do `vars.yml` (ver "Situação hoje", servidor);
- não há nenhum contentor da app no Mac, o `vault.yml` está cifrado e não há nenhum ficheiro decifrado no `git status`.

- A password do Vault está no Porta-chaves do Mac mini e no cofre de passwords pessoal do dono (confirmado a 19/10).

## Como retomar

1. Ler este ficheiro, o [plano geral](../../Infra%20da%20pizzaria%20contexto%20e%20plano.md) e o plano do próximo P.
2. Próxima ação: o [P5](planos/P5-compose-producao.md). Começa pelo passo 0, do dono: o token R2 do servidor, guardado no Vault. Do [P3](planos/P3-nome-local.md) falta só o teste sem internet.
3. Regras do dono (as mesmas do repositório da app):
   - o commit é sempre do dono: nunca `git add`, `commit` ou `push`. No fim de um P, deixar a árvore pronta e propor a mensagem;
   - nada corre contra o servidor sem autorização do dono nessa sessão. Primeiro `--check --diff`, depois a sério;
   - antes de executar, ver em que máquina se está (`hostname`). O Mac mini é `Matheuss-Mac-mini.local` e o servidor é `elitedeskserver`;
   - **a app não corre nos Macs (D2).** No Mac, o Docker serve para construir as imagens e para contentores temporários (o Postgres dos testes e o do drill de restauro). O servidor nunca recebe o código.
4. **Segredos. O agente nunca lê, mostra nem copia:**
   - a password do Vault e o `vault.yml` decifrado;
   - o `.env` do servidor (`/opt/daciaramella/.env`);
   - a chave privada `age`;
   - o `root.key` do Caddy.

   Os passos com segredos são do dono e estão marcados "dono". Fazem-se no Terminal do Mac, fora do VS Code. O dono nunca cola segredos no chat.

   **Atenção: isto é uma regra, não uma barreira técnica.**
   - O agente corre como o utilizador do dono, e o Porta-chaves entrega a password do Vault sem perguntar (D18). Por isso, qualquer comando do Ansible decifra o Vault em silêncio.
   - O agente nunca mostra valores do Vault, nem com o `debug`, e pede autorização antes de correr comandos contra o servidor.

## Situação hoje (18/10)

Verificado a 18/10 só com leituras, sem mudar nada.

- **Mac mini:**
  - Docker com `buildx`, que já constrói para `linux/amd64`;
  - a simulação da app parou no [P1](planos/P1-mac-ansible.md) (D2). Os dados ficaram nos volumes, e o Docker fica para o build;
  - `zstd` instalado;
  - Ansible instalado no P1 (ver o estado acima).
- **Servidor** (`elitedeskserver`, `10.77.0.10`):
  - Docker 29.1.3 e Compose 2.40.3, instalados pelo `base.yml` a 23/10 (P2), e ainda sem Tailscale;
  - `zstd` instalado;
  - fuso Europe/Lisbon desde 23/10 (P2);
  - o `sudo` pede password e é o `sudo-rs` 0.2.13, por omissão (`/usr/bin/sudo` → `/etc/alternatives/sudo` → `/usr/lib/cargo/bin/sudo`). O sudo clássico está em `/usr/bin/sudo.ws`. Com o `sudo-rs`, o `become` do Ansible falha por timeout à espera da pergunta da password, por isso o Ansible usa o `sudo.ws` (`ansible_become_exe`, P1, 18/10);
  - 162 GB livres na raiz.
- **App** (`daciaramella-system`, `main` em `a10bd1d`):
  - o `Dockerfile` usa `node:26-alpine`, uma tag que avança sozinha. O estágio final só leva o código já compilado (`dist`), as migrações e as dependências de produção, e não leva o código-fonte;
  - o `docker-compose.yml` é de desenvolvimento: usa `build:`, publica as portas 5432 e 3000, tem passwords com valor por omissão e não passa a `FATURACAO_REAL_ATIVA`;
  - as migrações correm no arranque, antes de a app abrir a porta, e todas numa só transação (Drizzle 0.44.7). Uma versão antiga com uma base de dados mais nova arranca sem aplicar nada;
  - o `/health` só faz `select 1`;
  - a Moloni entra por senha, sem callback, e usa a conta de testes 402495;
  - o `npm test` precisa de um Postgres (`DATABASE_URL_TEST`, por omissão `localhost:5432/daciaramella_test`);
  - **o `CLAUDE.md` e os documentos da app ainda assumem a app a correr no Mac** (`docker compose up` e o Postgres de desenvolvimento).
- **Nada está em produção.** A primeira instalação no servidor é limpa.

## Decisões

### Do dono, 18/10

Não se reabrem sem ele.

- **D1. Build no Mac, envio por SSH, sem registo de imagens e sem GitHub Actions.** Todo o contacto com a internet durante o build é do Mac: o Node, o npm, o Alpine, o Postgres e o Caddy. O Mac constrói as imagens x86 (`docker buildx`) e faz o deploy da app pronta no servidor.
- **D2. O servidor só corre a app. A app não corre nos Macs.**
  - O servidor recebe só o que precisa para correr: as imagens já construídas e a configuração (`compose.yml`, `.env` e `Caddyfile`). Nunca recebe o código, e não sai para a internet para construir.
  - Testar a app faz-se no servidor.
  - No Mac só correm contentores temporários, que desaparecem no fim: o Postgres do `npm test` e o do drill mensal de restauro.
- **D3. O rollback é uma cópia da base de dados feita no próprio Postgres antes de cada deploy** (`CREATE DATABASE rollback_<tag> TEMPLATE daciaramella`). Se o deploy falhar, repõe-se a cópia e arranca a imagem anterior. Não usa o backup cifrado: a chave privada não está no servidor, de propósito.
- **D4. O rollback com reposição de dados só se faz na noite do próprio deploy.** Depois de a loja abrir, corrige-se para a frente. Há duas alavancas para emergências: trocar só a imagem e pausar a faturação ([P8](planos/P8-alavancas-depois-de-abrir.md)).
- **D5. A primeira instalação é limpa.** Não há versão anterior nem rollback. Se correr mal, apaga-se e instala-se outra vez. O histórico de migrações até hoje não conta.
- **D6. A regra das migrações é uma boa prática, não um mecanismo.** Cada migração deve ser compatível com a versão anterior: acrescentar sim, renomear ou apagar só numa versão seguinte. Fica escrita no `CLAUDE.md` da app, sem teste automático.
- **D7. Em produção, os deploys fazem-se à segunda de manhã**, para haver dois dias de loja fechada para validar. A terça fica de reserva.
- **D8. Uma versão é a imagem e também a configuração.** O rollback repõe juntos a imagem, o `compose.yml`, o `.env` e o `Caddyfile`.
- **D9. Há uma lista de verificação depois de cada deploy**, porque o `/health` diz pouco ([P9](planos/P9-guia-e-ensaio-geral.md)).
- **D10. A tag em produção fica versionada no repositório da infra** (`app_tag`). Fazer deploy é mudar essa linha, correr o playbook e commitar só se correu bem.
  - A tag é a *tag* do Git da versão (`v0.1.0`), construída da `main` do GitHub com `construir.sh --release v0.1.0`.
  - Os testes (`construir.sh --test`, do `dev` local) têm a etiqueta `dev-<data-hora>`. Entram só no comando do deploy (`-e app_tag=…`) e não ficam no `vars.yml`.
  - Os dois modos foram decididos pelo dono a 23/10 ([P4](planos/P4-release-no-mac.md)).
- **D11. Nome local `app.figaro.local`**, num registo estático no router da loja ([P3](planos/P3-nome-local.md)).
  - Só a rede da loja acede à app.
  - Os Macs não acedem: quando for preciso, o dono usa o PC do balcão, por controlo remoto (mais tarde). A exceção é a fase da bancada, em que o Mac mini faz de PC do balcão (Q4).
  - Não há DNS público.
  - Mais tarde, o acesso à app vai ser limitado a IPs escolhidos. Isto fica para discutir e não muda o plano agora.
- **D12. Ansible em `ansible/`, na raiz do repositório.** O agente tinha proposto `infra/ansible/`. O dono mudou a pasta a 18/10, antes de fazer os seus passos do P1, e passou o plano geral para dentro de `infra/`.
- **D14. O `app.figaro.local` resolve-se no router, para os dois PCs Windows da loja (balcão e cozinha).** Confirmado pelo dono a 23/10.
  - O Windows pergunta ao router, e funciona.
  - Num Mac não abre, porque o macOS usa o Bonjour para os nomes `.local`.
  - Na bancada, o Mac mini resolve o nome com uma linha no `/etc/hosts` (Q4).
- **D16. A password do `sudo` do servidor fica no Vault** (`ansible_become_password`). Confirmado pelo dono a 18/10. O `become` usa o `sudo.ws`, porque o `sudo-rs` dá timeout. O Ansible entra como `mciaramella`: o dono pensou num utilizador técnico só para o Ansible e deixou-o para mais tarde (18 e 23/10).
- **D18. A password do Vault fica no Porta-chaves do Mac mini, sem confirmação.**
  - O `vault-pass.sh` lê-a com o `security`, que está na lista de acesso da entrada, por isso o Porta-chaves não pergunta nada.
  - Tem uma cópia no cofre de passwords do dono.
  - Consequência aceite pelo dono: qualquer programa que corra como ele, incluindo o agente, decifra o Vault sem perguntar.
  - A 18/10, o dono testou a confirmação obrigatória (uma janela por comando) e voltou atrás, porque aprovar cada comando era incómodo.

### Propostas pelo agente, por confirmar

- **D13. O Tailscale fica fora desta fase** (decidido pelo dono, 18/10).
  - Vai servir só para acesso de manutenção (SSH e deploy), nunca para a app, e o dono trata disso a seguir.
  - O ensaio previsto: o Mac mini ligado ao 5G do telemóvel do dono, a falar com o servidor pelo Tailscale.
  - Nesta fase, o Ansible liga-se pela rede da loja.
- **D15. A janela de manutenção está desligada no servidor de testes** (`janela_ativa: false`). Liga-se quando o servidor for para a loja.
- **D17. Todos os serviços de produção levam `pull_policy: never`.** O servidor nunca descarrega imagens: chegam todas do Mac.

### Por decidir (dono)

- **Q1. Backups do servidor para a R2: resolvida a 23/10, sim.** O servidor envia os backups para a R2, já nesta fase. O dono deixou ao agente a escolha do momento.
  - **P5:** um token R2 novo para o servidor, com os valores no Vault, e o `rclone.conf` como *template*.
  - **P6:** confirmar o primeiro envio.
  - **Pasta:** `teste_loja/` enquanto o servidor estiver na bancada, e `loja/` quando for para a loja. É uma linha no `vars.yml`, `rclone_remote`.
  - As duas regras de 90 dias do bucket (o bloqueio e o ciclo de vida) têm prefixo vazio, por isso valem também para `teste_loja/`. Os backups de teste apagam-se sozinhos aos 90 dias.
- **Q2. Drill mensal de restauro: resolvida a 18/10.** Continua no MacBook Pro, com contentores temporários (D2).
- **Q3. Domínio: resolvida a 18/10.** Não é preciso, porque o nome é local (D11).
- **Q4. Quem faz as verificações da app na bancada: resolvida a 18/10.**
  - Na bancada, o Mac mini faz de PC do balcão, ligado ao router, e é o dono que faz as verificações.
  - Para isso, o Mac mini tem a raiz do Caddy no Porta-chaves e uma linha `10.77.0.10  app.figaro.local` no `/etc/hosts`, que se apaga no fim da bancada ([P6](planos/P6-primeira-instalacao.md), passos 3 e 4).
- **Q5. O novo nome da app (Figaro): resolvida a 18/10.** O renaming é só visual, por agora. Os nomes técnicos continuam `daciaramella`: as imagens, a pasta `/opt/daciaramella`, a base de dados e o projeto Compose. A exceção é o nome na rede, que passa a ser `app.figaro.local` (D11).

## Ordem

```text
P1 Mac e Ansible ──► P2 Base do servidor ──┬──► P3 Nome local ─────────────┐
                                           └──► P5 Compose de produção ───┼──► P6 Primeira instalação ──► P7 Deploy com rollback ──► P8 Alavancas ──► P9 Guia e ensaio geral
P4 Release no Mac ──────────────────────────────────────────────────────────┘
```

O P4 não depende do servidor. O P5 precisa das tags do P4 e do Docker do P2, para validar.

## Por fazer

| Plano | O quê | Executa | Estado |
|---|---|---|---|
| [P1](planos/P1-mac-ansible.md), Mac e Ansible | Parar a simulação, Ansible no Mac mini, inventário, Vault | dono e agente | **feito** (18/10) |
| [P2](planos/P2-base-servidor.md), base do servidor | `base.yml` v1: Docker, logs, fuso, pastas, e o que já foi feito à mão | agente, com autorização | **feito** (23/10) |
| [P3](planos/P3-nome-local.md), nome local | `app.figaro.local` no router | dono e agente | em curso (23/10) |
| [P4](planos/P4-release-no-mac.md), release no Mac | Node fixo, `testar.sh` com Postgres temporário, `construir.sh --test/--release`, imagens de base, `CLAUDE.md` | agente (app e infra) | **feito** (23/10) |
| [P5](planos/P5-compose-producao.md), compose de produção | Modelos do compose, `.env` e `Caddyfile`, validados no servidor | agente | por fazer |
| [P6](planos/P6-primeira-instalacao.md), primeira instalação | `deploy.yml` em modo instalação, HTTPS, raiz do Caddy no Vault | agente e dono | por fazer |
| [P7](planos/P7-deploy-com-rollback.md), deploy com rollback | Cópia da base de dados, reposição automática, ensaios de falha | agente e dono | por fazer |
| [P8](planos/P8-alavancas-depois-de-abrir.md), alavancas | Repor a cópia, voltar à imagem anterior, pausar a faturação | agente e dono | por fazer |
| [P9](planos/P9-guia-e-ensaio-geral.md), guia e ensaio geral | Guia de deploy, lista de verificação, deploy feito só pelo dono | agente e dono | por fazer |

## Fora desta fase

- Tailscale, só para acesso de manutenção (D13). O ensaio é o Mac mini no 5G do telemóvel, a falar com o servidor.
- Proxy de saída e firewall nftables (Fase 2 do plano geral)
- `restauro.yml` e restauro completo a partir da R2. O envio dos backups para a R2 entrou nesta fase (Q1).
- Firewall do router por porta (Fase 4 do plano geral)
- O resto da base: chrony só para o router, espelho fixo do apt, MOTD e avisos do Ubuntu Pro, `snapd`, `open-vm-tools` e `smartd`
- O grupo `lxd` do `mciaramella` e o `lxd-installer`, um atalho para root sem password achado no P2. O dono deixou-o para depois a 23/10.
- Um utilizador técnico só para o Ansible, em vez do `mciaramella` (D16). Deixado para depois.
- Postos Windows e o certificado raiz neles
- Atualizar o resto dos documentos da app que assumem a app a correr no Mac (o `CLAUDE.md` muda no [P4](planos/P4-release-no-mac.md))
