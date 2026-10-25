# P8 — Alavancas para um problema depois do deploy

Estado: feito a 23/10 (falta só a parte de ponta a ponta do R4, com a Moloni, pelo dono) · Depende de: P7 · Bloqueia: P9 · Executa: agente e dono · Máquinas: Mac → servidor

## Objetivo

Ter provadas as três saídas para um problema descoberto depois de um deploy que correu bem (D4):

| Quando | O quê | Dados |
|---|---|---|
| Na mesma noite, antes de a loja abrir | `repor-copia.yml`: volta à versão anterior e à cópia da base de dados | Volta tudo ao estado de antes do deploy |
| Depois de a loja abrir | `deploy.yml` com a tag anterior: troca só a imagem | Mantém-se tudo |
| Problema na faturação, a qualquer hora | `faturacao.yml`: pausa a emissão | Mantém-se tudo; as faturas ficam em fila |

## 1. `repor-copia.yml` (mesma noite)

1. Mostra a tag da cópia, a hora a que foi feita e a diferença de comandas entre a `daciaramella` e a cópia.
2. **Se a `daciaramella` tiver comandas a mais, recusa** sem `-e perder_dados=sim`. É sinal de que a loja já trabalhou com a versão nova e de que a reposição apagaria vendas reais.
3. Pede confirmação (`pause`).
4. Para a `app` e o `backup` e troca as bases de dados:

   ```sql
   ALTER DATABASE daciaramella RENAME TO substituido_<tag_nova>;
   ALTER DATABASE rollback_<tag_anterior> RENAME TO daciaramella;
   ```

5. Repõe o pacote de `anterior/`, corre `up -d` e espera pelo `healthy`.
6. Escreve uma linha no `deploys.log`.
7. Lembra o dono de repor o `app_tag` anterior no `vars.yml`.

## 2. Deploy da tag anterior (depois de abrir)

Não precisa de código novo: é um `deploy.yml` normal, com o `app_tag` anterior (e `fora_da_janela=sim`, se for preciso). A imagem ainda está no servidor, porque o deploy guarda as 3 últimas tags.

- Funciona se as migrações do meio tiverem seguido a regra (D6).
- Se a versão anterior não arrancar com a base de dados nova, a própria reposição do [P7](P7-deploy-com-rollback.md) devolve a versão nova. É seguro por construção.
- **Limite:** o `/health` não deteta uma função partida, por exemplo uma tabela que a versão anterior usa e a nova apagou. Por isso a regra das migrações é um hábito a manter.

## 3. `faturacao.yml` (pausar a emissão)

- O valor vem da variável `faturacao_emissao_ativa` do `vars.yml`, que é a única fonte. O dono muda a linha e corre o playbook. Assim, o deploy seguinte não volta a ligar a emissão por engano.
- O playbook reescreve só o `.env`, recria só a `app` (cerca de 10 segundos sem serviço) e espera pelo `healthy`.
- **Pode correr fora da janela.** É uma alavanca de emergência para usar com a loja aberta.

## Passos

1. **(agente)** Escrever o `repor-copia.yml` e o `faturacao.yml`.
2. **(agente)** Pôr a `faturacao_emissao_ativa: 1` no `vars.yml` e no modelo do `.env`, se o P5 ainda não o tiver feito.
3. **(o dono autoriza)** Ensaios no servidor de testes.

## Aceitação

- **R1, mesma noite:** depois de um deploy bom (o E1 do P7), o `repor-copia.yml` volta à tag anterior, e as contagens e o `.env` ficam como antes do deploy.
- **R2, proteção:** depois de um deploy bom, criar uma comanda de teste. O `repor-copia.yml` recusa sem `perder_dados=sim`.
- **R3, depois de abrir, simulado:**
  1. fazer o deploy de `ensaio/aditiva`;
  2. criar 3 comandas de teste;
  3. fazer o deploy da tag anterior.

  A versão anterior arranca e as 3 comandas continuam lá.
- **R4, faturação:**
  - com `faturacao_emissao_ativa: 0`, os logs da `app` mostram que o worker de faturação não arranca, e uma venda de teste fica com a fatura pendente;
  - com `1`, o worker volta, e a fatura é emitida na conta de testes da Moloni.

## Riscos

- **Usar o `repor-copia.yml` depois de a loja abrir apaga vendas e faturas já comunicadas.** A proteção do passo 1.2 existe para isso. O `perder_dados=sim` é só para o servidor de testes.
- **Esquecer de repor o `app_tag` no `vars.yml`** depois de um `repor-copia.yml`. O deploy seguinte usaria a tag errada, e o playbook avisa no fim.

## Registo

**23/10, passos 1 e 2 (agente; o dono disse "pode ir direto"):**
- **`playbooks/repor-copia.yml`:**
  - lê a versão atual (`compose.yml`) e a anterior (`anterior/tag`) e confirma que existe a `rollback_<anterior>`;
  - mostra a hora da cópia (a hora do `anterior/tag`, no relógio do Mac) e as comandas na BD atual e na cópia;
  - **recusa se houver comandas a mais**, a não ser com `perder_dados=sim`;
  - pede confirmação (`pause`, escrever "sim"; `-e confirmar=sim` para os ensaios);
  - troca as BD: `daciaramella` → `substituido_<atual>` e `rollback_<anterior>` → `daciaramella`;
  - repõe o `anterior/`, arranca e confirma, e escreve no `deploys.log`. Se falhar a meio, mostra o estado e para;
  - lembra o `app_tag` do `vars.yml` (D10).
- **`playbooks/faturacao.yml`, diferente do plano em duas coisas:**
  - o `FATURACAO_EMISSAO_ATIVA` está no `compose.yml` (P5: os não-segredos vão no compose) e não no `.env`, por isso o playbook muda **só essa linha** do `compose.yml` instalado (`replace`) e não reescreve o pacote inteiro;
  - assim, uma mudança pendente no `vars.yml` (por exemplo, outro `app_tag`) nunca entra por esta porta sem cópia da BD.

  Recria só a app (o `compose up` só recria o serviço cuja configuração mudou), confirma o valor dentro da app (`printenv`) e escreve no `deploys.log`. Pode correr fora da janela.
- **`playbooks/vars/comum.yml`:** `pasta_app`, `pasta_raiz_caddy`, `psql` e `sql_cortar_ligacoes`, partilhados pelos três playbooks (`vars_files`).
- **O passo 2 já estava feito:** o `faturacao_emissao_ativa: 1` está no `vars.yml` desde o P5.

**23/10, ensaios (passo 3):**
- **Antes:** a cópia de segurança `p8_inicio` da BD (só o `admin`, 0 comandas, 14 migrações), reposta no fim.
- **As comandas de teste** foram inseridas por SQL (`INSERT INTO comandas (dia_negocio, numero_diario, modo) VALUES (current_date, 90x, 'teste')`). Os ensaios só contam comandas.
- **R1, mesma noite:**
  - o deploy bom (`v0.1.0` → `dev-2026-10-23-1638`) criou a `rollback_v0.1.0`;
  - o `repor-copia.yml` mostrou "Agora: dev-2026-10-23-1638… Volta para: v0.1.0, com a cópia de 2026-10-23 17:17…" e voltou à `v0.1.0` (`healthy`);
  - as contagens, as migrações e o `.env` ficaram iguais aos de antes do deploy;
  - ficou a `substituido_dev-2026-10-23-1638`, e o `deploys.log` diz "reposição da cópia".
- **R2, proteção:** depois de outro deploy bom e de 1 comanda de teste, o `repor-copia.yml` recusou com "A BD atual tem 1 comandas e a cópia tem 0: a loja já trabalhou com a dev-2026-10-23-1638…". Nada mudou.
- **R3, depois de abrir (simulado):**
  - versão aditiva `dev-2026-10-23-1719`, num clone descartável. A primeira tentativa, com uma coluna nova na `comandas`, **foi recusada pelo `construir.sh`**: um teste da app compara linhas inteiras da `comandas` (19 campos contra 18). Acrescentar uma coluna à `comandas` obriga a atualizar esse teste. Passou a uma **tabela nova** (`ensaio_aditiva`), também aditiva (D6);
  - deploy da aditiva (15 migrações, tabela nova), 3 comandas, e deploy da tag anterior (`-e app_tag=dev-2026-10-23-1638`);
  - **resultado:** a versão anterior arrancou `healthy` com a BD mais nova (15 migrações e a tabela lá), as 4 comandas ficaram, e não houve erros nos logs da app.
- **R4, faturação (o mecanismo):**
  - com `faturacao_emissao_ativa: 0`, o `faturacao.yml` (21 s) mudou só a linha (`"1"` → `"0"`) e recriou só a app (o Postgres continuou de pé). Dentro da app ficou `FATURACAO_EMISSAO_ATIVA=0`, e o `deploys.log` diz "emissão desligada";
  - o `deploy.yml` a seguir disse "Nada a fazer";
  - com `1`, o caminho inverso;
  - o `vars.yml` ficou igual ao do Git.
  - **Falta, pelo dono:** a parte de ponta a ponta, que precisa da Moloni ligada (o teste d do P6 apagou a ligação). Com `0`, uma venda fica com a fatura pendente; com `1`, é emitida na conta de testes.
- **Arrumação:**
  - voltou-se à `v0.1.0` pelo `deploy.yml` e repôs-se a `p8_inicio`;
  - apagadas as `substituido_*` e a `rollback_*` dos ensaios, a imagem e o ficheiro `dev-2026-10-23-1719` (no servidor e no Mac) e o clone;
  - no fim: `v0.1.0` `healthy`, só a BD `daciaramella` (só o `admin`, 0 comandas, 14 migrações), o HTTPS do Mac mini a funcionar, e o `deploy.yml` a dizer "Nada a fazer".
