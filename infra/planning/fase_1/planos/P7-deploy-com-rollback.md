# P7 — Deploy com cópia de rollback

Estado: por fazer · Depende de: P6 · Bloqueia: P8, P9 · Executa: agente e dono · Máquinas: Mac mini → servidor

## Objetivo

O deploy de uma versão nova, quando falha, volta sozinho à versão anterior, com a base de dados e a configuração exatamente como estavam (D3, D8).

## O fluxo do `deploy.yml`

### 1. Verificações (não mexem em nada)

- **A versão pedida existe** de uma de duas formas:
  - o ficheiro da release está em `release_dir`, o `sha256` bate certo e a etiqueta `revision` corresponde ao `app_tag`;
  - ou a imagem já está no servidor. É o caso de voltar a uma das 3 últimas versões ([P8](P8-alavancas-depois-de-abrir.md)).

  Se não existir de nenhuma forma, para e diz para correr primeiro o `release.sh`.
- **Se o servidor já estiver nessa tag, com a mesma configuração,** não faz nada e diz porquê.
- **Janela, só com `janela_ativa: true` (D15):**
  - hora de Lisboa, lida no servidor: das 01:00 às 06:00 todos os dias, e segunda e terça o dia todo;
  - recusa entre as 04:15 e as 04:45;
  - fora da janela, só com `-e fora_da_janela=sim`;
  - aviso, sem bloquear, se não for segunda (D7).
- **A versão atual está saudável.** Se não estiver, para, a não ser com `-e forcar=sim`.
- **Espaço livre:** pelo menos 5 GB.

Para ensaiar a verificação da janela, `-e agora_ensaio="AAAA-MM-DDTHH:MM"` substitui a hora do servidor.

### 2. Enviar e carregar

Só se o servidor ainda não tiver a imagem: copia o ficheiro, faz `docker load` e apaga o ficheiro (D2). Não mexe na loja.

### 3. Backup cifrado normal

`docker compose exec -T backup /app/backup.sh`. Se falhar, avisa e continua: a proteção do deploy é a cópia do passo 6. Este backup protege de um desastre, como o disco avariar.

### 4. Guardar o pacote atual

Copia `compose.yml`, `.env`, `Caddyfile` e um ficheiro `tag` para `/opt/daciaramella/anterior/` (D8).

### 5. Parar a app

`docker compose stop app backup`. O `CREATE DATABASE … TEMPLATE` exige que ninguém esteja ligado à base de dados.

### 6. Cópia de rollback

O playbook liga-se pelo `docker compose exec -T postgres psql -U daciaramella -d postgres`:

```sql
DROP DATABASE IF EXISTS rollback_<tag_antiga>;   -- a cópia do deploy anterior
CREATE DATABASE rollback_<tag_atual> TEMPLATE daciaramella;
```

Se a cópia falhar, o deploy para aqui, volta a arrancar a versão atual e termina com erro.

### 7. Trocar a versão

Valida o compose (tarefa `validar` do P5), escreve o pacote novo e corre `docker compose up -d`.

### 8. Esperar

Até 2 minutos pelo estado `healthy`, e depois o pedido pelo Caddy (como no P6).

### 9a. Se correu bem

- Escreve uma linha no `deploys.log`: data, tag anterior, tag nova e `ok`.
- Apaga as imagens `app` e `backup` antigas, mas guarda as 3 últimas tags.
- Lista as bases de dados `falhado_*` que ainda existam, como aviso.
- Lembra a lista de verificação ([P9](P9-guia-e-ensaio-geral.md)).

A cópia `rollback_<tag_atual>` fica até ao deploy seguinte. É ela que o [P8](P8-alavancas-depois-de-abrir.md) usa para voltar atrás ainda na mesma noite.

### 9b. Se falhou: reposição automática

1. Guarda os logs da `app` no Mac, em `{{ release_dir }}/logs/deploy-<data>-<tag_nova>.log`.
2. `docker compose stop app backup`.
3. Troca as bases de dados:

   ```sql
   ALTER DATABASE daciaramella RENAME TO falhado_<tag_nova>;
   ALTER DATABASE rollback_<tag_atual> RENAME TO daciaramella;
   ```

4. Repõe o pacote de `anterior/`.
5. `docker compose up -d` e espera pelo `healthy`.
6. Escreve uma linha no `deploys.log` e termina **com erro**: "deploy de X falhou; voltou para Y".
7. **Se a versão anterior também não arrancar:** para, mostra o estado das bases de dados e dos contentores, e não tenta mais nada. O que fazer a seguir está no guia ([P9](P9-guia-e-ensaio-geral.md)).

## Passos

1. **(agente) Completar o `deploy.yml`.** O modo de instalação do P6 continua a funcionar quando não existe `compose.yml`.
2. **(agente, repositório da app) Ramos descartáveis para os ensaios,** que nunca se juntam à `main` e se apagam no fim. Cada um precisa de um commit, para o `release.sh` ter uma tag, e esses commits são feitos ou autorizados pelo dono:
   - `ensaio/boa`: só muda um texto;
   - `ensaio/arranque-falha`: um `throw` na primeira linha do `index.ts`, antes das migrações;
   - `ensaio/migracao-e-falha`: uma migração que cria a tabela `ensaio_rollback`, e um `throw` logo a seguir a `aplicarMigrations()`;
   - `ensaio/aditiva`: uma migração que só acrescenta uma coluna com `DEFAULT` (é para o P8).

   A release de cada um faz-se com o `release.sh`, no ramo. Os `throw` não partem o `npm test`, porque os testes não importam o `index.ts`.
3. **(o dono autoriza) Ensaios no servidor de testes.**
4. **(agente) Limpar no fim:**
   - apagar as bases `falhado_*` dos ensaios;
   - apagar as imagens `ensaio` no servidor e no Mac, e os ficheiros de release desses ramos;
   - apagar os ramos `ensaio/*`;
   - voltar à tag de `main`.

## Aceitação

Antes de cada ensaio, contar as comandas (`select count(*) from comandas`), as linhas de `drizzle.__drizzle_migrations` e o `sha256` do `.env`.

- **E1, versão boa** (`ensaio/boa`):
  - o deploy corre bem;
  - existe `rollback_<tag anterior>`;
  - o `anterior/` tem o pacote antigo;
  - há uma linha `ok` no `deploys.log`;
  - a pasta `releases/` está vazia.
- **E2, falha antes das migrações** (`ensaio/arranque-falha`):
  - volta sozinho e termina com erro;
  - a tag a correr é a anterior;
  - as contagens são iguais às de antes;
  - existe `falhado_<tag>`.
- **E3, falha depois de uma migração** (`ensaio/migracao-e-falha`):
  - volta sozinho;
  - a tabela `ensaio_rollback` não existe na `daciaramella`, mas existe na `falhado_<tag>`;
  - o número de linhas das migrações é igual ao de antes.
- **E4, `.env` reposto:** num ensaio de falha com uma variável a mais no modelo do `.env`, o `sha256` do `.env` no fim é igual ao de antes.
- **E5, janela:** com `-e janela_ativa=true` e `agora_ensaio` numa quarta às 15:00, ou num dia qualquer às 04:30, o deploy recusa sem mexer em nada.
- **E6, nada a fazer:** correr outra vez o deploy do E1, com a mesma tag e a mesma configuração, não envia nada, não para a app e não faz outra cópia.
- **E7, versão atual partida:** com a `app` parada à mão, o deploy recusa sem `forcar=sim`.
- **E8, versão inexistente:** com um `app_tag` sem ficheiro de release e sem imagem no servidor, o deploy recusa sem mexer em nada.

## Riscos

- **A cópia falha se houver ligações à base de dados.** Por isso a app e o backup param antes. Se mesmo assim falhar, o deploy para antes de trocar a versão.
- **A cópia está no mesmo disco da base de dados.** Não protege de uma avaria do disco; para isso há o backup cifrado do passo 3.
- **Uma versão `healthy` pode ter funções partidas,** porque o `/health` só faz `select 1`. Para isso há a lista de verificação do [P9](P9-guia-e-ensaio-geral.md).
- **Esquecer bases `falhado_*` a ocupar disco.** O deploy lista-as em cada corrida.
