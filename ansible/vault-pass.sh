#!/bin/sh
# Password do Vault, lida do Porta-chaves do Mac mini (D18). Não guarda nada em disco.
# A entrada é criada pelo dono no passo 4 do P1.
exec security find-generic-password -a daciaramella-infra -s ansible-vault -w
