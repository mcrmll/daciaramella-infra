# P8 — Alavancas para um problema depois do deploy

Estado: por fazer · Depende de: P7 · Bloqueia: P9 · Executa: agente e dono · Máquinas: Mac → servidor

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
