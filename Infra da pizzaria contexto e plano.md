# Infra da pizzaria: contexto e plano

Oct 9, 2026 · @ciaramella

## Âmbito e princípios

Este documento é a referência da infraestrutura da pizzaria de Viana do Castelo: um servidor local sempre ligado, dois postos (balcão e cozinha) e a rede que os liga. Serve de contexto para o projeto de infra e deve ser atualizado sempre que uma decisão mudar.

Cada ponto está marcado como **Decidido** (dito pelo dono) ou **Proposto** (recomendação ainda por confirmar).

**Dentro do âmbito**

- Rede da loja e regras entre equipamentos
- Servidor: sistema, saídas para a internet, proxy e firewall
- Acesso remoto por Tailscale
- HTTPS e nome DNS interno
- Deploy da aplicação e CI
- Backups e restauro, na parte que toca à infra

**Fora do âmbito**

- Acesso remoto e manutenção dos PCs do balcão e da cozinha (o dono trata à parte)
- TPA do BPI, que vive no Wi-Fi da MEO e não integra com a aplicação
- Funcionalidades da aplicação

**Princípios**

1. A loja funciona sem internet. Pedidos, cozinha e balcão nunca dependem de ligação externa.
2. O servidor só fala com uma lista fechada de destinos.
3. Há um só operador, remoto, na Suíça. Tudo tem de ser recuperável à distância.
4. Toda a configuração vive em ficheiros versionados: Ansible, compose e configuração do router.
5. Manutenção só nas janelas com a loja fechada: todos os dias das 01:00 às 06:00, e segunda e terça o dia todo.

## Inventário e compras

Faltam três compras para a infra funcionar: o router próprio, uma UPS e cabos. Os computadores, os ecrãs e a impressora já existem.

**O que já existe**

| Equipamento | Função | Estado |
| --- | --- | --- |
| HP EliteDesk 800 G3 Mini | Servidor (Ubuntu Server) | Comprado, nada instalado |
| PC e ecrã do balcão | Posto Windows com internet geral | Comprado |
| PC e ecrã da cozinha | Posto Windows sem internet | Comprado |
| Impressora térmica de rede | Impressão de talões | Comprada |
| Router da MEO | Acesso à internet e Wi-Fi do TPA | Do operador |
| TPA BPI | Pagamentos, no Wi-Fi da MEO | Do banco |

**O que falta comprar**

| Item | Qtd | Para quê | Preço e notas |
| --- | --- | --- | --- |
| Router [MikroTik hEX refresh (E50UG)](https://mikrotik.com/product/hex_2024) | 1 | Router próprio atrás do da MEO: firewall, DNS e NTP da loja | Escolha confirmada. Preço sugerido de 59,95 dólares. 5 portas gigabit, transformador incluído, sem Wi-Fi |
| UPS line-interactive de 700 a 900 VA, com porta USB de dados e tomadas Schuko | 1 | Mantém router da MEO, router próprio e servidor ligados e permite desligar o servidor em segurança | Cerca de 80 a 125 €. Exemplo: [APC BX750MI-GR](https://www.pccomponentes.pt/apc-bx750mi-gr-ups-750va-410w), 410 W, 4 tomadas com bateria, USB tipo B |
| Cabos Ethernet Cat6 | 5 troços | MEO ao router, router ao servidor, ao balcão, à cozinha e à impressora | Comprimentos a medir no local |
| Cabos de alimentação com ficha Schuko | 1 por aparelho comprado na Suíça | As fichas suíças de 3 pinos não entram nas tomadas portuguesas | Confirmar o conector de cada transformador antes de comprar |
| Pen USB de 8 GB ou mais | 1 | Instalador do Ubuntu Server | Serve qualquer uma que já exista |

**Porquê o hEX e não o L009**

O hEX refresh cumpre todos os requisitos da rede com o mesmo RouterOS do L009, por cerca de metade do preço sugerido (59,95 contra 119 dólares). As 5 portas ficam todas ocupadas: MEO, servidor, balcão, cozinha e impressora. Se um dia for precisa mais uma, liga-se um switch simples a uma das portas; os equipamentos nesse switch partilham o mesmo segmento.

**Opcional, mais tarde**

- SSD SATA de 2,5 polegadas no servidor, só para backups locais, se a baía estiver livre
- Segundo mini PC de reserva, já configurado, para trocar em caso de avaria

**Não é preciso comprar**

Switch, ponto de acesso Wi-Fi ou licenças de software. Ubuntu, Docker, Caddy e Squid são livres. O Tailscale tem plano gratuito; confirmar os limites atuais no momento de configurar.

## Rede

O router próprio fica atrás do router da MEO e é a única fronteira da rede da loja. Tudo o que está do lado da MEO, incluindo o Wi-Fi e o TPA, é tratado como rede não confiável.

**Decidido**

- Internet da MEO. O Wi-Fi da MEO não é para clientes e serve o TPA do BPI.
- Um router próprio, o MikroTik hEX refresh (E50UG), ligado ao router da MEO.
- Servidor, balcão, cozinha e impressora ligados por cabo ao router próprio.
- O balcão tem internet geral (sites, WhatsApp). A cozinha não tem internet.

**Proposto**

- Configuração do router (RouterOS) exportada em texto e guardada no repositório.
- Cada equipamento na sua porta, com regras de firewall entre portas. As 5 portas do hEX ficam todas ocupadas.
- Sub-rede interna diferente da da MEO e da de casa, por exemplo 10.77.0.0/24, para não colidir com rotas do Tailscale.
- Sem Wi-Fi no router próprio.
- IPs fixos por reserva DHCP para servidor, postos e impressora.
- O router serve DNS (com o registo do nome interno da aplicação) e NTP à rede.
- NAT duplo aceite, porque nada entra de fora.

**Quem fala com quem**

| Origem | Destino | Permitido |
| --- | --- | --- |
| Lado da MEO (Wi-Fi, TPA, internet) | Rede da loja | Nada entra |
| Balcão | Internet | Tudo |
| Balcão | Servidor | Só HTTPS, porta 443 |
| Cozinha | Internet | Nada |
| Cozinha | Servidor | Só HTTPS, porta 443 |
| Servidor | Router | DNS (53) e NTP (UDP 123) |
| Servidor | Internet | Só a lista de saídas permitidas |
| Servidor | Impressora | Porta de impressão, a confirmar (normalmente TCP 9100) |
| Balcão e cozinha | Impressora | Nada, salvo decisão em contrário |
| Servidor | Balcão e cozinha | Nada iniciado pelo servidor |

## Servidor e saídas permitidas

O servidor é o HP EliteDesk com Ubuntu Server e Docker, e só pode sair para os destinos da tabela abaixo. Tudo o resto é negado.

**Sistema**

- Ubuntu Server, sempre ligado. Decidido.
- Versão 26.04 LTS. Proposto.
- Docker e Compose instalados a partir dos repositórios do Ubuntu, para não acrescentar destinos. Proposto.
- Atualizações de segurança automáticas, com reinício dentro da janela de manutenção e depois do backup das 04:30. Proposto.
- BIOS configurada para arrancar sozinha após corte de energia. Proposto.
- Disco sem cifra, por agora. Decidido. Compensa-se com backups cifrados, chave privada do backup fora do servidor e segredos que se podem rodar.

**Saídas permitidas**

| Destino | Porta | Quem usa | Estado |
| --- | --- | --- | --- |
| Router próprio (DNS) | 53 | Sistema | Decidido |
| Router próprio (NTP) | UDP 123 | Sistema | Decidido |
| `api.moloni.pt` e `www.moloni.pt` | 443 | Aplicação | Decidido |
| `<conta>.eu.r2.cloudflarestorage.com` | 443 | Backup | Decidido |
| `archive.ubuntu.com` e `security.ubuntu.com` | 80 | apt | Proposto |
| `pkgs.tailscale.com` | 443 | apt | Proposto |
| Tailscale (coordenação, relays e ligações diretas) | TCP 443 e UDP | tailscaled | Proposto |

O DNS e o NTP passam pelo router próprio, que é quem fala com o exterior. O endpoint da R2 leva o `.eu.`. Não há registo de imagens na lista: as imagens chegam já construídas do Mac mini (ver CI e deploy).

**Como se aplica** (proposto)

1. Um proxy de saída (Squid) com a lista por nome é o único componente com rota para fora.
2. A aplicação e o backup ficam numa rede Docker interna e saem pelo proxy, através de `HTTPS_PROXY`.
3. A firewall do servidor (nftables) nega toda a saída que não seja o proxy, o tailscaled, o DNS e o NTP.
4. O router repete a regra em versão grossa, para continuar de pé se o servidor for comprometido.
5. O tailscaled não passa pelo proxy, para que um erro no proxy não corte o acesso remoto.

**A validar no ensaio**

- O Node 26.7 respeita `HTTPS_PROXY` com `NODE_USE_ENV_PROXY=1`, desde que o cliente HTTP da aplicação não use um agente próprio.
- O rclone respeita as variáveis de proxy e usa o endpoint da conta, sem subdomínio por bucket.
- Um pedido a um domínio fora da lista falha e fica registado no proxy.

**Sem alerta externo**

Por decisão atual não há serviço de heartbeat. Se a loja ficar sem internet ou o servidor parar, ninguém é avisado. Acrescentar um mais tarde é uma linha na tabela.

## Acesso remoto e HTTPS

O Tailscale no servidor é o único canal de manutenção, e a aplicação é servida em HTTPS com um nome DNS interno.

**Tailscale**

- Instalado só no servidor. Decidido.
- Operado a partir do Mac mini, na Suíça, só para manutenção (SSH e deploy). A app não se acede pelo Tailscale. Decidido.
- Ligação direta: o tailscaled pode sair em UDP para qualquer IP, mais TCP 443. Proposto. A [documentação da Tailscale](https://tailscale.com/docs/reference/faq/firewall-ports) avisa que enumerar os relays permitidos acaba por partir a conectividade.
- ACL de folha: o servidor tem uma tag própria, só o dono lhe chega por SSH, e o servidor não inicia ligações para nada do tailnet. Proposto. Protege as máquinas de casa se o servidor da loja for comprometido.

**HTTPS e nome interno**

- HTTPS com nome de DNS interno. Decidido. Nada configurado ainda.
- Nome: `app.figaro.local`, definido só como registo estático no router, que responde sem internet. Só a rede da loja acede à app; os Macs não. Não há DNS público. Decidido a 18 out 2026 ([fase 1, P3](infra/planning/fase_1/planos/P3-nome-local.md)).
- Certificado: Caddy à frente da aplicação, com a sua CA interna, sem depender da internet. Proposto.
- O certificado raiz do Caddy instala-se uma vez no Windows do balcão e da cozinha.
- A pasta de dados do Caddy é um volume persistente e entra no backup. Se se perder, o Caddy gera outra raiz e é preciso reinstalá-la nos dois PCs.
- `MOLONI_ORIGEM_GESTAO` passa a ser o nome HTTPS. É a verificação de origem dos pedidos da Gestão à Moloni. A Moloni entra por senha (`grant_type: password`), por isso não há callback a registar.

## Aplicação e deploy

A aplicação corre em Docker Compose com três serviços, e o deploy é feito só pelo dono, do Mac mini, direto para a loja.

**O que o compose tem hoje**

| Serviço | Imagem | O que faz |
| --- | --- | --- |
| `postgres` | `postgres:17-alpine` | Base de dados, com volume `pgdata` |
| `app` | Construída do repositório, Node 26.7 | Aplicação na porta 3000, fuso Europe/Lisbon, worker de faturação Moloni |
| `backup` | Construída de `ops/backup` | Backup diário às 04:30, cifrado com `age`, enviado por `rclone` para a R2, retenção local de 30 |
| `restauro` | A mesma do backup | Só corre a pedido, pelo perfil `restauro` |

**O que muda para produção** (proposto)

1. Tirar a publicação da porta `5432` do Postgres. Hoje fica acessível a toda a rede, com a password por omissão.
2. Trocar as passwords com valor por omissão (`${VAR:-valor}`) por `${VAR:?}`, que falha se o `.env` faltar.
3. Trocar `build: .` por `image:` com a tag do commit (`${APP_TAG:?}`). A imagem chega já construída do Mac, e o compose de produção nunca descarrega imagens (`pull_policy: never`).
4. Deixar de publicar a porta `3000`. Só o Caddy expõe a 443.
5. Acrescentar um healthcheck à aplicação, necessário para o rollback automático.
6. Tirar a chave privada `age` do servidor. O backup só precisa da chave pública; a privada copia-se apenas para restaurar.
7. Limitar o tamanho dos logs do Docker no `daemon.json`.
8. Fixar a imagem do Postgres por digest. O Mac descarrega-a e envia-a ao servidor pelo mesmo caminho das outras.

**CI e deploy**

- Repositório privado no GitHub, sem nada no Actions. Facto atual.
- Deploy só pelo dono, do Mac mini, pelo Tailscale, direto para a loja, sem staging. Decidido.
- **Imagens construídas no Mac mini**, sem registo de imagens nem GitHub Actions. Todo o contacto com a internet durante o build é do Mac. **Decidido a 18 out 2026.** Um script de release:
  - recusa avançar com alterações por commitar;
  - corre os testes com um Postgres temporário;
  - constrói `app` e `backup` com `docker buildx --platform linux/amd64` e a tag do commit;
  - guarda-as em ficheiro (`docker save`).

  O Mac mini é ARM e o servidor é x86, por isso o build é emulado e mais lento.
- **O servidor só corre a app.** Recebe por SSH as imagens já construídas e a configuração, e nunca o código. Não sai para a internet para receber um deploy, nem guarda nenhum token de registo. A app deixa de correr nos Macs. **Decidido a 18 out 2026.**
- O GitHub não guarda nenhuma credencial com acesso à loja. Proposto.
- A tag em produção fica versionada no repositório da infra (`app_tag` no inventário). Fazer deploy é mudar essa linha, commitar e correr o playbook.
- Playbook de deploy em Ansible. Antes de cada deploy, faz uma cópia da base de dados no próprio Postgres. Se o deploy falhar, repõe sozinho a cópia, a imagem anterior e a configuração anterior (`compose.yml`, `.env` e `Caddyfile`). **Decidido a 18 out 2026.**
- O rollback com reposição de dados só se faz na noite do deploy. Depois de a loja abrir, corrige-se para a frente, com duas alavancas: trocar só a imagem e pausar a faturação. Os deploys fazem-se à segunda, e há uma lista de verificação depois de cada um. **Decidido a 18 out 2026.**
- A regra das migrações (acrescentar sim; renomear ou apagar só numa versão seguinte) é uma boa prática, sem teste automático. **Decidido a 18 out 2026.**
- Plano detalhado em [infra/planning/fase_1](infra/planning/fase_1/ESTADO.md).
- Playbook de base separado (utilizadores, SSH, firewall, proxy, Docker, Tailscale), corrido raramente. Proposto.
- Deploys e reinícios só nas janelas de manutenção, fora das 04:30 do backup.

## Plano por fases

Oito fases, de 0 a 7, pela ordem em que se desbloqueiam. As fases 1 a 5 fazem-se na Suíça, com o equipamento na bancada; só a fase 6 exige estar em Viana.

### Fase 0: decisões e compras

- [ ] Confirmar ou corrigir os pontos marcados como Proposto neste documento
- [ ] Fechar os pontos em aberto da última secção
- [ ] Encomendar o router, a UPS e os cabos
- [ ] Escolher o nome DNS interno e a sub-rede

### Fase 1: servidor base

- [ ] BIOS: atualizar, ativar o arranque após corte de energia, confirmar o TPM 2.0
- [x] Instalar o Ubuntu Server, com a decisão sobre disco cifrado já tomada (sem cifra)
- [ ] Criar o repositório de infra com Ansible
- [ ] Playbook de base: utilizadores, SSH só por chave, fuso Europe/Lisbon, atualizações automáticas, Docker
- [ ] Instalar o Tailscale com tag própria e aplicar a ACL de folha
- [ ] Confirmar o acesso por SSH pelo Tailscale a partir do Mac mini

### Fase 2: saídas controladas

- [ ] Instalar o proxy de saída com a lista de destinos
- [ ] Pôr o apt a sair pelo proxy
- [ ] Aplicar a firewall do servidor com negação por omissão
- [ ] Testar: um domínio fora da lista falha; Moloni, R2 e apt funcionam
- [ ] Confirmar que o Tailscale continua a funcionar com a firewall ativa

### Fase 3: aplicação em produção

- [ ] Escrever o compose de produção com as oito alterações
- [ ] Pôr o Caddy à frente da aplicação, com a CA interna e o nome escolhido
- [ ] Escrever o script de release no Mac: testes com Postgres temporário, imagens x86 com a tag do commit, ficheiro para enviar
- [ ] Fixar a imagem do Postgres por digest e enviá-la pelo mesmo caminho
- [ ] Escrever o playbook de deploy com backup, verificação de saúde e rollback
- [ ] Validar que a aplicação e o backup saem pelo proxy
- [ ] Fazer um restauro completo a partir da R2

### Fase 4: rede da loja, na bancada

- [ ] Configurar o router: WAN, portas, reservas DHCP, DNS estático, NTP e firewall
- [ ] Exportar a configuração do router para o repositório
- [ ] Ligar os dois PCs dos postos e instalar o certificado raiz do Caddy
- [ ] Validar a tabela de quem fala com quem, linha a linha
- [ ] Dar IP fixo à impressora e imprimir um talão a partir do servidor

### Fase 5: ensaio geral

- [ ] Cortar a internet: o serviço continua, a faturação fica em fila e retoma sozinha
- [ ] Cortar a energia: a UPS aguenta, o servidor desliga em segurança e volta a arrancar sozinho
- [ ] Reiniciar o servidor: todos os serviços sobem sem intervenção
- [ ] Fazer um deploy e um rollback pelo Tailscale
- [ ] Rever os registos do proxy à procura de pedidos negados inesperados

### Fase 6: instalação em Viana

- [ ] Levar os cabos de alimentação com ficha portuguesa
- [ ] Ligar o router próprio ao router da MEO e confirmar que as sub-redes não colidem
- [ ] Mudar as passwords de gestão e de Wi-Fi do router da MEO
- [ ] Confirmar o Tailscale a partir de fora da loja
- [ ] Fazer o primeiro backup e um restauro de teste já na loja

### Fase 7: operação

- [ ] Escrever o guia de operação: deploy, restauro, o que fazer se o servidor não ligar
- [ ] Deixar na loja uma folha simples para quem lá está: que cabos e que botão
- [ ] Rever os registos do proxy e da firewall ao fim da primeira semana

## Pontos em aberto

Nove pontos ainda por decidir ou confirmar. Os três primeiros condicionam compras ou a fase 1.

- [x] Disco do servidor cifrado ou não? Se sim, tem de desbloquear sozinho pelo TPM, porque ninguém estará lá para escrever uma password. **Decidido a 16 out 2026: sem cifra, por agora**, porque desbloquear à distância seria demasiado difícil. A proteção faz-se por outros meios (ver Sistema).
- [x] Nome DNS interno final e sub-rede da loja. **Sub-rede decidida a 16 out 2026: 10.77.0.0/24. Nome decidido a 18 out 2026: `app.figaro.local`.**
- [ ] Onde fica fisicamente a impressora, e é o servidor que lhe envia os talões?
- [ ] Que cliente HTTP usa a aplicação para chamar a Moloni (fetch nativo, axios, outro)? Decide como se configura o proxy.
- [ ] As migrações da base de dados correm sozinhas no arranque da aplicação? Como se desfaz uma migração num rollback?
- [ ] Onde vivem os segredos (Moloni, R2, passwords, chave do backup): `.env` no servidor, Ansible Vault, outro?
- [ ] As janelas de manutenção (01:00 às 06:00, segunda e terça) são em hora de Portugal?
- [ ] Alerta externo: fica sem, por decisão atual. Rever depois do primeiro mês de loja aberta.
- [ ] Os PCs do balcão e da cozinha correm uma versão do Windows ainda com atualizações de segurança? Está fora do âmbito, mas o balcão tem internet geral e está na mesma rede do servidor.
