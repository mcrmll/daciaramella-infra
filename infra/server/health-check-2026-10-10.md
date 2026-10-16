# Health check do servidor

10 out 2026 · @ciaramella

Primeira verificação geral do servidor depois da instalação do Ubuntu, ainda na bancada, na Suíça. Serve de base para comparar com verificações futuras. As horas estão em UTC, que é o fuso atual do servidor.

## Resumo

O hardware está aprovado. O SSH passou a aceitar só chave e há uma firewall provisória. Faltam algumas verificações da BIOS e a decisão sobre a cifra do disco.

| Área | Estado | Notas |
| --- | --- | --- |
| CPU e RAM | OK | Teste de esforço de 10 min passou, máximo de 53 °C |
| Disco | OK, a vigiar | SMART passou, 99 % de vida; SSD de cerca de 2015 com 3 contadores a acompanhar |
| Espaço | OK | Raiz estendida de 100 para 180 GiB, 55 GiB livres no VG |
| Arranque | OK | Reboot limpo, 0 unidades falhadas |
| Sistema | OK | Totalmente atualizado, kernels antigos removidos |
| Rede | Funcional | DNS, NTP, fuso e sub-rede ainda não seguem o plano |
| Segurança | OK, provisória | SSH só por chave; `ufw` ativo até ao nftables da Fase 2 |

## Identificação

Comandos: `hostnamectl`, `uptime`.

| Item | Valor |
| --- | --- |
| Hostname | `elitedeskserver` |
| Modelo | HP EliteDesk 800 G3 DM 35W (SKU Y3A16AV) |
| Asset tag | 8CG80821GG |
| BIOS | P21 Ver. 02.38, de 2021-04-21 (KBC 06.29) |
| Sistema | Ubuntu 26.04.1 LTS, x86-64 |
| Kernel | 7.0.0-38-generic |
| Carga em repouso | 0,00 |

No início havia 2 utilizadores ligados: a sessão SSH e um login esquecido na consola local (tty1). Depois do reboot ficou só a sessão SSH.

## CPU e memória

Comandos: `free -h`, `vmstat 1 5`, `top -bn1`.

| Item | Valor | Leitura |
| --- | --- | --- |
| RAM | 7,1 GiB total, 490 MiB usados, 6,6 GiB disponíveis | 8 GB físicos; o resto fica reservado à gráfica integrada |
| Swap | 4 GiB, 0 usados | Normal |
| CPU | 97,8 a 100 % idle, `wa` 0, `st` 0 | Sem espera de disco |
| Processos | 134, 0 zombies | Normal |

## Disco e partições

Comandos: `df -hT`, `lsblk -f`, `vgs`, `pvs`.

| Dispositivo | Tamanho | Uso |
| --- | --- | --- |
| `sda` | 238,5 GiB | SSD SATA |
| `sda1` | 1 GiB, vfat | `/boot/efi`, 1 % |
| `sda2` | 2 GiB, ext4 | `/boot`, 11 % |
| `sda3` | 235,4 GiB, LVM | PV do `ubuntu-vg` |
| `ubuntu-vg/ubuntu-lv` | 180 GiB, ext4 | `/`, 4 % de 176,6 GB |

- O instalador deixou a raiz com 100 GiB e 135 GiB livres no VG. Foi estendida com `lvextend -r -L +80G /dev/ubuntu-vg/ubuntu-lv`, deixando 55,4 GiB livres para snapshots ou um volume de backups locais.
- **O disco não está cifrado:** o LVM assenta direto na `sda3`, sem LUKS.

## SMART do SSD

Comandos: `smartctl -i`, `smartctl -H`, `smartctl -A`, `smartctl -t short`, `smartctl -l selftest`.

| Item | Valor |
| --- | --- |
| Modelo | SanDisk SD9SB8W-256G-1006 (família Marvell, 2,5 polegadas) |
| Número de série | 1838C9800936 |
| Firmware | X6104006 |
| Capacidade | 256 060 514 304 bytes |
| Interface | SATA 3.3, 6,0 Gb/s; TRIM disponível |
| Avaliação global | PASSED |
| Teste curto | Completed without error, às 20 423 h |

**Leitura:** saudável e com baixo desgaste. As 20 423 horas são tempo ligado; o disco quase não foi escrito (atributos 173, 201 e 249).

**A vigiar** (nenhum é motivo de troca):

- **174, perdas de energia inesperadas: 33 em 89 arranques.** Se subir sem cortes de energia conhecidos, há problema de alimentação. Reforça a necessidade da UPS.
- **181 com 34 350 610 e 176 com 768.** O valor normalizado do 181 chegou a 74 e recuperou para 92. Nestes SanDisk/Marvell costuma ser ruído do firmware, mas são os únicos contadores de falhas que não estão a zero.
- **241, 312 915 GiB escritos**, incoerente com os atributos 173, 201 e 249. Provavelmente usa outra unidade neste firmware.

**Base de atributos, para comparar no futuro:**

```text
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  1 Raw_Read_Error_Rate     0x002f   100   100   050    Pre-fail  Always       -       27162
  5 Reallocated_Sector_Ct   0x0033   100   100   005    Pre-fail  Always       -       0
  9 Power_On_Hours          0x0032   100   100   ---    Old_age   Always       -       20423
 12 Power_Cycle_Count       0x0032   100   100   ---    Old_age   Always       -       89
171 Program_Fail_Count      0x0032   100   100   ---    Old_age   Always       -       0
172 Erase_Fail_Count        0x0032   100   100   ---    Old_age   Always       -       0
173 Avg_Write/Erase_Count   0x0032   100   100   005    Old_age   Always       -       7
174 Unexpect_Power_Loss_Ct  0x0032   100   100   ---    Old_age   Always       -       33
176 Erase_Fail_Count_Chip   0x0022   100   100   ---    Old_age   Always       -       768
181 Program_Fail_Cnt_Total  0x0022   092   074   ---    Old_age   Always       -       34350610
183 Runtime_Bad_Block       0x0032   100   100   ---    Old_age   Always       -       0
184 End-to-End_Error        0x003b   100   100   097    Pre-fail  Always       -       0
187 Reported_Uncorrect      0x0032   100   100   ---    Old_age   Always       -       0
188 Command_Timeout         0x0032   100   100   ---    Old_age   Always       -       1
194 Temperature_Celsius     0x0022   036   056   ---    Old_age   Always       -       36 (Min/Max 16/56)
198 Offline_Uncorrectable   0x0030   100   100   ---    Old_age   Offline      -       0
199 SATA_CRC_Error          0x0032   100   100   ---    Old_age   Always       -       0
201 Lifetime_Remaining%     0x0023   099   099   005    Pre-fail  Always       -       993
230 Perc_Write/Erase_Count  0x0032   100   100   ---    Old_age   Always       -       350 350 70
241 Total_Writes_GiB        0x0032   100   100   ---    Old_age   Always       -       312915
242 Total_Reads_GiB         0x0032   100   100   ---    Old_age   Always       -       658736
243 Unknown_Marvell_Attr    0x0032   100   100   ---    Old_age   Always       -       525198
244 Thermal_Throttle        0x0032   000   100   ---    Old_age   Always       -       0
249 TLC_NAND_GB_Writes      0x0032   100   100   ---    Old_age   Always       -       1569
```

## Atualizações

Comando: `apt update && apt upgrade -y && apt autoremove -y`.

- 21 pacotes atualizados, entre eles `thermald`, `netplan.io`, `libaudit1`, `rust-coreutils`, `mdadm` e `sos`.
- 2 pacotes em *phasing*, ou seja, ainda não libertados pelo Ubuntu para todos: `open-iscsi` e `libopeniscsiusr`.
- Kernel antigo 7.0.0-30 removido (319 MB). Fica só o 7.0.0-38.
- Espelhos usados: `ch.archive.ubuntu.com` e `security.ubuntu.com`.
- Avisos sem efeito: `File descriptor 3 leaked on vgs invocation` (do `grub-probe` com LVM) e `os-prober will not be executed`.

## Reinício

O reboot foi pedido pelo `needrestart`, para os serviços e as sessões passarem a usar os binários atualizados.

| Item | Resultado |
| --- | --- |
| Regresso | SSH disponível em menos de 3 min, sem intervenção |
| `systemctl --failed` | 0 unidades |
| `journalctl -p err -b` | Só `x86/cpu: SGX disabled or unsupported by BIOS`, inofensivo |

## Temperatura

Comandos: `sensors` (lm-sensors), atributo 194 do SMART.

| Sensor | Em repouso | Limites |
| --- | --- | --- |
| CPU, pacote | 32 °C | Alto a 84 °C, crítico a 100 °C |
| CPU, núcleos 0 a 3 | 29 a 32 °C | Idem |
| SSD | 30 a 36 °C | Máximo histórico de 56 °C |
| Ventoinha | Não exposta (`pwm1: N/A`) | — |

## Teste de esforço

Comando: `stress-ng --cpu 0 --vm 2 --vm-bytes 75% --timeout 600s --metrics-brief`, com `watch -n2 sensors` noutro terminal.

| Item | Resultado |
| --- | --- |
| Carga | 4 workers de CPU e 2 de memória (2,32 GB cada, 4,65 GB no total) |
| Duração | 10 min 1,8 s |
| Resultado | 6 passaram, 0 falharam, 0 ignorados |
| Temperatura máxima | 53 °C |

O `stress-ng` avisou que o governador de frequência está em `powersave`. No `intel_pstate` este modo já escala a frequência dinamicamente e é o adequado para um servidor quase sempre em repouso, por isso ficou como está.

## Rede

Comandos: `ip -br a`, `ip r`, `resolvectl status`, `timedatectl`, `ss -tulpn`.

| Item | Valor |
| --- | --- |
| Interface | `eno1`, 192.168.1.28/24 |
| Gateway | 192.168.1.1 (router de casa) |
| IPv6 global | 2001:1708:4082:7c00:12e7:c6ff:fe05:902a/64 |
| DNS | 192.168.1.1, mais 194.230.55.96, 212.98.37.130 e 2001:1700:a00::19 (do operador) |
| Fuso | Etc/UTC |
| Relógio | Sincronizado, pelo chrony |

**Portas à escuta:**

| Porta | Endereço | Processo |
| --- | --- | --- |
| TCP 22 | 0.0.0.0 e [::] | `sshd`, por socket do systemd |
| TCP e UDP 53 | 127.0.0.53 e 127.0.0.54 | `systemd-resolved` |
| UDP 323 | 127.0.0.1 e [::1] | `chronyd` (porta de controlo) |
| UDP 546 | link-local do `eno1` | `systemd-networkd` (cliente DHCPv6) |

## Segurança

Comandos: `sshd -T`, `ufw status verbose`, `systemctl status unattended-upgrades`, `ls /dev/tpm*`.

**Estado encontrado**

| Item | Valor |
| --- | --- |
| `PermitRootLogin` | no |
| `PubkeyAuthentication` | yes |
| `PasswordAuthentication` | **yes** |
| Firewall | `ufw` instalado mas inativo |
| `unattended-upgrades` | Ativo |
| TPM | `/dev/tpm0` e `/dev/tpmrm0`: TPM 2.0 presente |

O `PasswordAuthentication yes` vinha do `50-cloud-init.conf`, criado pelo instalador. Já existia um `99-hardening.conf` com `PasswordAuthentication no`, mas não tinha efeito: o `sshd` aplica o primeiro valor que lê, e os ficheiros de `sshd_config.d/` são lidos por ordem alfabética.

**Alterações feitas**

1. `99-hardening.conf` renomeado para `/etc/ssh/sshd_config.d/10-hardening.conf`, com `KbdInteractiveAuthentication no` acrescentado. Conteúdo final:

   ```text
   PasswordAuthentication no
   PermitRootLogin no
   KbdInteractiveAuthentication no
   ```

2. Testes a partir do Mac:

   | Teste | Resultado |
   | --- | --- |
   | SSH forçado só com chave | `CHAVE_OK` |
   | SSH normal | `ENTRA_COM_CHAVE` |
   | SSH forçado só com password | `Permission denied (publickey)` |

3. `ufw` ativado (com `IPV6=yes`):

   ```text
   Status: active
   Logging: on (low)
   Default: deny (incoming), allow (outgoing), disabled (routed)

   To                         Action      From
   22/tcp                     ALLOW IN    192.168.1.0/24             # SSH bancada
   ```

O `ufw` é provisório, até ao nftables da Fase 2. As saídas continuam todas abertas.

## Incidente: corte de energia (11 out 2026)

Um corte de eletricidade em casa, durante a noite, desligou o servidor à bruta. Quando a luz voltou, o servidor ficou desligado: a BIOS ainda tinha *After Power Loss* no valor de omissão. Teve de ser ligado no botão.

| Verificação | Resultado |
| --- | --- |
| `systemctl --failed` | 0 unidades |
| `dmesg` (ext4) | `orphan cleanup on readonly fs` na raiz, seguido de `re-mounted r/w`. Limpeza normal depois de um corte, sem erros |
| SMART 174 (perdas de energia inesperadas) | 33 → 34 |
| SMART 12 (ciclos de energia) | 89 → 90 |

Sem danos. Confirma, num caso real, duas necessidades do plano: *After Power Loss → Power On* na BIOS, para voltar sozinho, e a UPS, para não desligar à bruta.

## Por verificar

- [ ] Teste de SSH depois de ativar o `ufw` (`ssh mciaramella@192.168.1.28 'echo FIREWALL_OK'`)
- [ ] Erros do kernel depois do teste de esforço: `dmesg --level=err,warn` e `journalctl -k -b | grep -Ei 'mce|thermal|throttl|oom'`
- [x] BIOS: *After Power Loss → Power On* (feito a 16 out 2026)
- [ ] BIOS: estado do Secure Boot (`mokutil --sb-state`)
- [ ] BIOS: confirmar no site da HP se a P21 02.38 é a última versão
- [x] Teste de corte de energia: tirar a ficha com o servidor ligado e confirmar que arranca sozinho (passou a 16 out 2026; o SSH voltou sem tocar no botão)
- [ ] Opcional: Memtest86+ pela consola local
- [ ] Decidir se o disco fica cifrado. Se sim, é preciso reinstalar, de preferência antes do playbook de base

## Implicações para o plano

1. **Espelho do apt.** O servidor usa `ch.archive.ubuntu.com`, e a tabela de saídas permitidas lista `archive.ubuntu.com`. Fixar o espelho no Ansible e usar esse nome na lista.
2. **IPv6.** O servidor recebe IPv6 global. A firewall do servidor (tabela `inet` no nftables) e a do router têm de cobrir IPv6, ou o IPv6 é desativado no servidor.
3. **DNS.** O `systemd-resolved` tem os DNS do operador como alternativa ao router. Fixar só o router no netplan (`dhcp4-overrides: use-dns: false`).
4. **Fuso e NTP.** Passar o fuso para Europe/Lisbon e apontar o chrony só para o router.
5. **Saídas do sistema.** Desativar o MOTD-news, os avisos do Ubuntu Pro/ESM e decidir sobre o `snapd`, para não aparecerem como pedidos negados no proxy.
6. **cloud-init.** Não faz falta num servidor físico. Desativá-lo (`/etc/cloud/cloud-init.disabled`) evita que volte a escrever configuração do SSH.
7. **Docker e `ufw`.** O Docker passa por cima do `ufw`: uma porta em `ports:` fica aberta mesmo com a firewall ativa.
8. **Mudança de sub-rede.** A regra do `ufw` só aceita SSH de 192.168.1.0/24. Antes de mudar para a sub-rede da loja, o Tailscale tem de estar a funcionar, com `ufw allow in on tailscale0`, ou o nftables tem de já ter substituído o `ufw`.
9. **SSH por socket.** No Ubuntu 26.04 o SSH arranca pelo `ssh.socket`. Limitar o SSH a uma interface faz-se com `ListenStream` no socket, não com `ListenAddress` no `sshd_config`.
10. **UPS.** O histórico de 33 cortes bruscos no SSD reforça a UPS com desligamento automático por USB.
11. **Alterações manuais por passar para Ansible:** extensão do LVM, `10-hardening.conf` e regras do `ufw`.
