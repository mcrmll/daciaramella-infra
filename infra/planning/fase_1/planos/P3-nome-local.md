# P3 — Nome na rede da loja

Estado: feito a 23/10 (o teste no browser faz parte do P6) · Depende de: P2 · Bloqueia: P6 · Executa: dono e agente (cada passo diz quem) · Máquinas: router

## Objetivo

- **A app abre na rede da loja por `https://app.figaro.local` (D11).** Só a rede da loja acede à app.
- **Os Macs não acedem à app.** Quando for preciso, o dono usa o PC do balcão, por controlo remoto (mais tarde). A exceção é a fase da bancada: aí, o Mac mini faz de PC do balcão, ligado ao router (Q4 do [ESTADO](../ESTADO.md)).
- **O Tailscale fica fora desta fase (D13).** Nesta fase, o Ansible liga-se ao servidor pela rede da loja.

## Como o nome resolve

```text
PC do balcão / cozinha ── "onde fica app.figaro.local?" ──► router hex-loja ── registo fixo ──► 10.77.0.10
```

- Os PCs da loja recebem o router como DNS por DHCP. O router responde sozinho, **mesmo sem internet** (princípio 1 do plano geral).
- Não há DNS público nem domínio a registar.
- **`.local` (D14):** o Windows pergunta ao router e funciona. O macOS usa o Bonjour para os nomes `.local` e não pergunta ao router, por isso num Mac o nome não abre. Os postos da loja são Windows, por isso serve. Na bancada, o Mac mini resolve o nome com uma linha no `/etc/hosts` ([P6](P6-primeira-instalacao.md), passo 4).

## Passos

### Passo 1 — o nome no router (dono)

1. `/ip dns static add name=app.figaro.local address=10.77.0.10 comment="app"`
2. Acrescentar a mesma linha ao [`hex-loja.rsc`](../../../router/hex-loja.rsc).

### Passo 2 — o nome no Ansible (agente)

`app_nome: app.figaro.local` no `vars.yml`. Daqui saem o `Caddyfile` e o `MOLONI_ORIGEM_GESTAO` ([P5](P5-compose-producao.md)).

## Aceitação

- **O nome resolve pelo router:** na bancada, do Mac mini, `nslookup app.figaro.local 10.77.0.1` devolve `10.77.0.10`. O comando pergunta diretamente ao router. Na loja, num PC Windows, `nslookup app.figaro.local` deve devolver o mesmo, com o servidor DNS `10.77.0.1`; isto confirma-se quando os PCs forem ligados.
- **Sem internet:** com o cabo da WAN do router desligado, o nome continua a resolver.
- **No browser,** depois do [P6](P6-primeira-instalacao.md): `https://app.figaro.local` abre no Mac mini, a fazer de PC do balcão.

## Riscos

- **Num Mac ou num iPhone, o `app.figaro.local` não abre sem uma linha no `/etc/hosts`** (Bonjour). Na bancada, o Mac mini tem essa linha ([P6](P6-primeira-instalacao.md), passo 4). Fora disso, é intencional.

## Registo

**23/10:**
- **Passo 1 (dono):** o registo `app.figaro.local → 10.77.0.10` está no router. Do Mac mini, `nslookup app.figaro.local 10.77.0.1` devolve `10.77.0.10`.
- **Passo 2 (agente):** `app_nome: app.figaro.local` no `vars.yml`.
- **Router no Git:** `/export` novo, feito a 23/10. O `hex-loja.rsc` tem agora a reserva DHCP do servidor e o registo `app.figaro.local`, as duas únicas mudanças reais. O export sai do router com CRLF e foi convertido para LF.
- **Sem internet (dono, 23/10):** com o cabo da WAN do router desligado, o nome continua a resolver. OK.
- O teste no browser fica para a aceitação do [P6](P6-primeira-instalacao.md).
