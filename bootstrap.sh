#!/bin/bash
# ============================================
# Bootstrap N8N Backup System
# Download inicial para nova VM
# Execute: curl -sSL https://raw.githubusercontent.com/SEU_USUARIO/n8n-backup/main/bootstrap.sh | bash
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
echo "║    N8N Backup System - Bootstrap v2.0  ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📦 Preparando instalação...${NC}"

# Verificar se já existe
if [ -d "/opt/n8n-backup" ]; then
    echo -e "${YELLOW}⚠️  /opt/n8n-backup já existe${NC}"
    read -p "Sobrescrever? (s/N): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        echo "Cancelado"
        exit 0
    fi
fi

# Criar diretório
sudo mkdir -p /opt/n8n-backup
sudo chown $USER:$USER /opt/n8n-backup
cd /opt/n8n-backup

# URL do repositório (ALTERAR PARA SEU REPO)
REPO_URL="https://raw.githubusercontent.com/SEU_USUARIO/n8n-backup/main"

echo -e "${BLUE}📥 Baixando arquivos...${NC}"

# Scripts principais
curl -sSL "${REPO_URL}/setup-prod.sh" -o setup-prod.sh
curl -sSL "${REPO_URL}/setup-backup.sh" -o setup-backup.sh
curl -sSL "${REPO_URL}/backup-prod.sh" -o backup-prod.sh
curl -sSL "${REPO_URL}/restore-backup.sh" -o restore-backup.sh
curl -sSL "${REPO_URL}/config.env" -o config.env

# Biblioteca
mkdir -p lib
curl -sSL "${REPO_URL}/lib/setup.sh" -o lib/setup.sh
curl -sSL "${REPO_URL}/lib/logger.sh" -o lib/logger.sh
curl -sSL "${REPO_URL}/lib/security.sh" -o lib/security.sh
curl -sSL "${REPO_URL}/lib/generate-rclone.sh" -o lib/generate-rclone.sh
curl -sSL "${REPO_URL}/lib/postgres.sh" -o lib/postgres.sh

echo -e "${GREEN}✓ Arquivos baixados${NC}"

echo -e "${BLUE}🔧 Configurando permissões...${NC}"
chmod +x setup-prod.sh setup-backup.sh backup-prod.sh restore-backup.sh
chmod +x lib/*.sh

echo -e "${GREEN}✓ Permissões configuradas${NC}"

# Criar estrutura de diretórios
mkdir -p backups/local logs lib schemas

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    DOWNLOAD CONCLUÍDO! 🎉             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Próximos passos:${NC}"
echo ""
echo -e "${YELLOW}Para VM de PRODUÇÃO:${NC}"
echo "   cd /opt/n8n-backup"
echo "   sudo ./setup-prod.sh"
echo ""
echo -e "${YELLOW}Para VM de BACKUP:${NC}"
echo "   cd /opt/n8n-backup"
echo "   sudo ./setup-backup.sh"
echo ""