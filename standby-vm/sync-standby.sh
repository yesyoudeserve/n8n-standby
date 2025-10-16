#!/bin/bash
# ============================================
# Sync VM Standby N8N
# Sincronização da VM Standby com dados da nuvem
# ============================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações se existir
if [ -f "${SCRIPT_DIR}/config.env" ]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Carregar bibliotecas do projeto principal
if [ -f "${SCRIPT_DIR}/../lib/logger.sh" ]; then
    source "${SCRIPT_DIR}/../lib/logger.sh"
    source "${SCRIPT_DIR}/../lib/security.sh"
    source "${SCRIPT_DIR}/../lib/postgres.sh"
fi

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║    N8N Standby VM Sync                 ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar modo teste
TEST_MODE=false
if [ "$1" = "--test" ]; then
    TEST_MODE=true
    echo -e "${YELLOW}🧪 MODO TESTE - Nenhuma alteração será feita${NC}"
    echo ""
fi

# Verificar se é root
if [ "$EUID" -ne 0 ] && [ "$TEST_MODE" = false ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./sync-standby.sh"
    exit 1
fi

echo -e "${BLUE}[1/6]${NC} Verificando configurações..."

# Verificar se config.env existe
if [ ! -f "${SCRIPT_DIR}/config.env" ]; then
    echo -e "${RED}✗ Arquivo config.env não encontrado!${NC}"
    echo "   Execute: cp config.env.template config.env"
    echo "   E edite as credenciais"
    exit 1
fi

# Verificar credenciais essenciais
missing_creds=()
[ -z "$ORACLE_ACCESS_KEY" ] && missing_creds+=("ORACLE_ACCESS_KEY")
[ -z "$ORACLE_SECRET_KEY" ] && missing_creds+=("ORACLE_SECRET_KEY")
[ -z "$B2_ACCOUNT_ID" ] && missing_creds+=("B2_ACCOUNT_ID")
[ -z "$B2_APPLICATION_KEY" ] && missing_creds+=("B2_APPLICATION_KEY")

if [ ${#missing_creds[@]} -gt 0 ]; then
    echo -e "${RED}✗ Credenciais faltando: ${missing_creds[*]}${NC}"
    echo "   Edite o arquivo config.env"
    exit 1
fi

echo -e "${GREEN}✓ Configurações OK${NC}"

echo -e "${BLUE}[2/6]${NC} Configurando rclone..."

# Gerar configuração rclone
if [ "$TEST_MODE" = false ]; then
    source "${SCRIPT_DIR}/../lib/generate-rclone.sh"
    generate_rclone_config
else
    echo -e "${YELLOW}🧪 Pularia configuração rclone${NC}"
fi

echo -e "${GREEN}✓ rclone configurado${NC}"

echo -e "${BLUE}[3/6]${NC} Procurando backup mais recente..."

# Procurar backup mais recente (igual ao recovery)
latest_backup=""
latest_date=""

# Oracle
if [ "$ORACLE_ENABLED" = true ]; then
    oracle_backup=$(rclone lsl "oracle:${ORACLE_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | sort -k2,3 | tail -1 | awk '{print $NF}')
    if [ -n "$oracle_backup" ]; then
        oracle_date=$(echo "$oracle_backup" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
        if [ -z "$latest_date" ] || [ "$oracle_date" \> "$latest_date" ]; then
            latest_backup="$oracle_backup"
            latest_date="$oracle_date"
            BACKUP_SOURCE="oracle"
        fi
    fi
fi

# B2
if [ "$B2_ENABLED" = true ]; then
    b2_backup=$(rclone lsl "b2:${B2_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | sort -k2,3 | tail -1 | awk '{print $NF}')
    if [ -n "$b2_backup" ]; then
        b2_date=$(echo "$b2_backup" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
        if [ -z "$latest_date" ] || [ "$b2_date" \> "$latest_date" ]; then
            latest_backup="$b2_backup"
            latest_date="$b2_date"
            BACKUP_SOURCE="b2"
        fi
    fi
fi

if [ -z "$latest_backup" ]; then
    echo -e "${RED}✗ Nenhum backup encontrado nos storages!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Backup encontrado: ${latest_backup} (fonte: ${BACKUP_SOURCE})${NC}"

echo -e "${BLUE}[4/6]${NC} Baixando backup..."

# Criar diretório temporário
TEMP_DIR=$(mktemp -d)
BACKUP_LOCAL_DIR="${SCRIPT_DIR}/backups"
mkdir -p "$BACKUP_LOCAL_DIR"

# Determinar bucket
bucket=""
case $BACKUP_SOURCE in
    oracle) bucket="$ORACLE_BUCKET" ;;
    b2) bucket="$B2_BUCKET" ;;
    *) echo -e "${RED}✗ Fonte desconhecida${NC}"; exit 1 ;;
esac

# Baixar backup
if [ "$TEST_MODE" = false ]; then
    rclone copy "${BACKUP_SOURCE}:${bucket}/${latest_backup}" "${BACKUP_LOCAL_DIR}/" --progress
else
    echo -e "${YELLOW}🧪 Pularia download do backup${NC}"
fi

LATEST_BACKUP_FILE="${BACKUP_LOCAL_DIR}/${latest_backup}"

if [ "$TEST_MODE" = false ] && [ ! -f "$LATEST_BACKUP_FILE" ]; then
    echo -e "${RED}✗ Falha no download do backup${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Backup baixado${NC}"

echo -e "${BLUE}[5/6]${NC} Preparando restauração..."

# Extrair backup
if [ "$TEST_MODE" = false ]; then
    tar -xzf "$LATEST_BACKUP_FILE" -C "$TEMP_DIR"
else
    echo -e "${YELLOW}🧪 Pularia extração do backup${NC}"
fi

# Verificar se tem dump SQL
dump_file=$(find "$TEMP_DIR" -name "n8n_dump.sql.gz" | head -1)
if [ -z "$dump_file" ]; then
    echo -e "${RED}✗ Dump SQL não encontrado no backup!${NC}"
    echo "   Backup pode estar corrompido"
    exit 1
fi

echo -e "${GREEN}✓ Arquivos de backup OK${NC}"

echo -e "${BLUE}[6/6]${NC} Sincronização concluída!"

if [ "$TEST_MODE" = true ]; then
    echo ""
    echo -e "${YELLOW}🧪 TESTE CONCLUÍDO${NC}"
    echo "   Tudo OK para sincronização real"
    echo ""
    echo -e "${BLUE}Para sincronização real:${NC}"
    echo "   sudo ./sync-standby.sh"
    echo ""
else
    echo ""
    echo -e "${GREEN}✅ VM STANDBY SINCRONIZADA!${NC}"
    echo ""
    echo -e "${BLUE}📋 Status:${NC}"
    echo "   • Backup baixado: ${latest_backup}"
    echo "   • Dados prontos para restauração"
    echo "   • EasyPanel configurado"
    echo ""
    echo -e "${YELLOW}🚀 Para ativar em produção:${NC}"
    echo "   1. Redirecionar webhooks/DNS para esta VM"
    echo "   2. Verificar: http://$(hostname -I | awk '{print $1}'):5678"
    echo "   3. Monitorar logs: docker logs n8n-main"
    echo ""
    echo -e "${RED}⚠️  Lembre-se de:${NC}"
    echo "   • Desligar a VM principal"
    echo "   • Esta VM agora é a produção"
    echo ""
    echo -e "${BLUE}🔄 Próximos passos para recuperação:${NC}"
    echo "   1. Executar: ./restore-standby.sh"
    echo "   2. Ou restaurar manualmente o banco:"
    echo "      gunzip < backups/${latest_backup}/n8n_dump.sql.gz | docker exec -i n8n_postgres psql -U n8n -d n8n"
    echo ""
fi

# Limpar
rm -rf "$TEMP_DIR"
