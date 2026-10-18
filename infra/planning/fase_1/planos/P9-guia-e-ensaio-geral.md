# P9 — Guia de deploy, lista de verificação e ensaio geral

Estado: por fazer · Depende de: P7, P8 · Bloqueia: — · Executa: agente (guia e fecho) e dono (ensaio) · Máquinas: Mac mini → servidor

## Objetivo

O dono faz um deploy completo sozinho, só com o guia. É a prova de que a fase está fechada.

## Passos

### Passo 1 — `docs/operacao/deploy.md` (agente)

1. **Quando:**
   - no servidor de testes (`janela_ativa: false`), a qualquer hora;
   - em produção (`janela_ativa: true`), à segunda de manhã (D7), com a terça de reserva. Nunca entre as 04:15 e as 04:45. Fora da janela, só com um motivo escrito no `deploys.log`.
2. **No dia a dia:** os testes correm no Mac com `ops/testar.sh`, com um Postgres temporário. A app em si só se testa no servidor (D2).
3. **Um deploy, por ordem:**
   1. no repositório da app, `ops/release.sh`, que testa, constrói e deixa o ficheiro em `~/daciaramella-releases/`;
   2. pôr no `vars.yml` o `app_tag` que a release mostrar;
   3. `ansible-playbook playbooks/deploy.yml`;
   4. a lista de verificação;
   5. o commit do `app_tag`.
4. **Lista de verificação, cerca de 5 minutos:**
   1. no PC do balcão (na bancada, o Mac mini a fazer de balcão), abrir `https://app.figaro.local`, sem aviso de certificado;
   2. entrar na Gestão;
   3. criar uma comanda em modo teste no balcão e vê-la na cozinha (tempo real);
   4. imprimir o talão;
   5. em Sistema → Moloni, confirmar que a ligação está viva;
   6. confirmar a última linha do `deploys.log` e o último backup.
5. **Se alguma coisa correr mal:**

   | Sintoma | O que fazer |
   |---|---|
   | O `release.sh` falhou nos testes | Corrigir e voltar a correr. Para repetir só esses testes, usar `ops/testar.sh` com um filtro |
   | O deploy falhou e voltou sozinho | Ler o log em `~/daciaramella-releases/logs/`, corrigir e fazer outra release |
   | O deploy falhou e a versão anterior também não arranca | Ver o estado mostrado pelo playbook. Repor a cópia à mão, com os comandos do P7 (9b.3). Se não der, restaurar o backup cifrado da noite |
   | Problema encontrado na mesma noite | `repor-copia.yml` ([P8](P8-alavancas-depois-de-abrir.md)) |
   | Problema encontrado depois de a loja abrir | Corrigir para a frente, ou fazer o deploy da tag anterior |
   | Faturas erradas ou em excesso | `faturacao_emissao_ativa: 0` e `faturacao.yml`, depois investigar |

6. **Onde está cada coisa:**
   - no servidor: `/opt/daciaramella/` (`compose.yml`, `.env`, `Caddyfile`, `anterior/`, `caddy/` e `deploys.log`). A pasta `releases/` só tem ficheiros durante um deploy. O servidor nunca tem o código;
   - no Mac mini: `~/daciaramella-releases/`, com os ficheiros de release e os logs;
   - os segredos: no Vault, com a password no Porta-chaves e no cofre de passwords.

### Passo 2 — ensaio geral (dono, sem o agente)

1. A partir do Mac mini, fazer o deploy de uma versão nova da `main`, seguindo só o guia.
2. Anotar cada dúvida ou passo que falte. O agente corrige o guia depois.

### Passo 3 — fecho (agente)

1. Atualizar o [ESTADO](../ESTADO.md) com o estado de cada P e o resultado do ensaio.
2. No [plano geral](../../../../Infra%20da%20pizzaria%20contexto%20e%20plano.md), marcar o que ficou feito nas Fases 1 e 3 e escrever que o deploy está descrito nesta fase.
3. Criar um ponto de situação novo em `docs/status/`.
4. Confirmar no `git status` que não há segredos decifrados.
5. Propor ao dono a mensagem do commit.

## Aceitação

- O dono fez o deploy só com o guia. As dúvidas que teve passaram a correções no guia.
- A lista de verificação foi feita e passou.
- O plano geral e o ESTADO dizem o que existe.

## Riscos

- **O guia desatualiza-se** à medida que os playbooks mudam. Regra: cada alteração a um playbook atualiza o guia no mesmo commit.
