#!/bin/bash
# ============================================
# Backup Automático VM Produção N8N
# Para ser executado na VM Principal
# ============================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║   N8N Production Backup (Standby)      ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./backup-production.sh"
    exit 1
fi

# Verificar se está na VM produção (não standby)
if [ -f "/opt/n8n-backup/standby-vm/setup-standby.sh" ]; then
    echo -e "${YELLOW}⚠️  Parece que está na VM Standby!${NC}"
    echo "   Este script deve rodar na VM Produção"
    echo ""
    echo -e "${BLUE}Se quiser mesmo executar aqui:${NC}"
    read -p "Continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

echo -e "${BLUE}[1/3]${NC} Verificando sistema N8N..."

# Verificar se o sistema N8N está instalado
if [ ! -d "/opt/n8n-backup" ]; then
    echo -e "${RED}✗ Sistema N8N não encontrado!${NC}"
    echo "   Instale primeiro: https://github.com/yesyoudeserve/n8n-backup"
    exit 1
fi

# Verificar se backup.sh existe
if [ ! -f "/opt/n8n-backup/backup.sh" ]; then
    echo -e "${RED}✗ Script de backup não encontrado!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Sistema N8N OK${NC}"

echo -e "${BLUE}[2/3]${NC} Executando backup completo..."

# Executar backup completo
cd /opt/n8n-backup
./backup.sh

echo -e "${GREEN}✓ Backup concluído${NC}"

echo -e "${BLUE}[3/3]${NC} Verificando upload..."

# Verificar se backup foi enviado para a nuvem
BACKUP_FILE=$(ls -t /opt/n8n-backup/backups/local/n8n_backup_*.tar.gz 2>/dev/null | head -1)

if [ -z "$BACKUP_FILE" ]; then
    echo -e "${RED}✗ Arquivo de backup não encontrado!${NC}"
    exit 1
fi

BACKUP_NAME=$(basename "$BACKUP_FILE")

# Verificar Oracle
if [ -f "/opt/n8n-backup/config.env" ]; then
    source /opt/n8n-backup/config.env

    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone lsf "oracle:${ORACLE_BUCKET}/" | grep -q "$BACKUP_NAME"; then
            echo -e "${GREEN}✓ Backup enviado para Oracle${NC}"
        else
            echo -e "${YELLOW}⚠️  Backup não encontrado no Oracle${NC}"
        fi
    fi

    if [ "$B2_ENABLED" = true ]; then
        if rclone lsf "b2:${B2_BUCKET}/" | grep -q "$BACKUP_NAME"; then
            echo -e "${GREEN}✓ Backup enviado para B2${NC}"
        else
            echo -e "${YELLOW}⚠️  Backup não encontrado no B2${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    BACKUP PRODUÇÃO CONCLUÍDO! 🎉       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Resumo:${NC}"
echo "   • Arquivo: ${BACKUP_NAME}"
echo "   • VM Standby pode sincronizar"
echo "   • Próximo backup automático: daqui 3h"
echo ""
echo -e "${YELLOW}💡 Para configurar backup automático:${NC}"
echo "   # Editar crontab"
echo "   sudo crontab -e"
echo "   # Adicionar linha:"
echo "   0 */3 * * * /opt/n8n-backup/standby-vm/backup-production.sh"
echo ""
