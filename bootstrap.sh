#!/bin/bash
# ============================================
# Bootstrap N8N Backup System
# Download e setup inicial para nova VM
# Execute: curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh | bash
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
echo "║    N8N Backup System - Bootstrap       ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📦 Baixando sistema de backup...${NC}"

# Criar diretório
sudo mkdir -p /opt/n8n-backup
sudo chown $USER:$USER /opt/n8n-backup
cd /opt/n8n-backup

# Baixar todos os arquivos principais
REPO_URL="https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main"

echo "Baixando arquivos principais..."
curl -sSL "${REPO_URL}/bootstrap.sh" -o bootstrap.sh
curl -sSL "${REPO_URL}/install.sh" -o install.sh
curl -sSL "${REPO_URL}/n8n-backup.sh" -o n8n-backup.sh
curl -sSL "${REPO_URL}/backup.sh" -o backup.sh
curl -sSL "${REPO_URL}/restore.sh" -o restore.sh
curl -sSL "${REPO_URL}/backup-easypanel-schema.sh" -o backup-easypanel-schema.sh
curl -sSL "${REPO_URL}/config.env" -o config.env
curl -sSL "${REPO_URL}/rclone.conf" -o rclone.conf

echo "Baixando biblioteca..."
mkdir -p lib
curl -sSL "${REPO_URL}/lib/logger.sh" -o lib/logger.sh
curl -sSL "${REPO_URL}/lib/menu.sh" -o lib/menu.sh
curl -sSL "${REPO_URL}/lib/postgres.sh" -o lib/postgres.sh
curl -sSL "${REPO_URL}/lib/security.sh" -o lib/security.sh
curl -sSL "${REPO_URL}/lib/recovery.sh" -o lib/recovery.sh
curl -sSL "${REPO_URL}/lib/monitoring.sh" -o lib/monitoring.sh
curl -sSL "${REPO_URL}/lib/setup.sh" -o lib/setup.sh
curl -sSL "${REPO_URL}/lib/upload.sh" -o lib/upload.sh
curl -sSL "${REPO_URL}/lib/generate-rclone.sh" -o lib/generate-rclone.sh

echo -e "${GREEN}✓ Sistema baixado${NC}"

echo -e "${BLUE}🔧 Configurando permissões...${NC}"
chmod +x install.sh n8n-backup.sh bootstrap.sh backup.sh restore.sh backup-easypanel-schema.sh
chmod +x lib/*.sh

echo -e "${GREEN}✓ Permissões configuradas${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    DOWNLOAD CONCLUÍDO! 🎉             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Próximos passos:"
echo ""
echo "   cd /opt/n8n-backup"
echo "   sudo ./install.sh"
echo ""
echo "💡 O instalador irá configurar tudo interativamente!"
echo ""