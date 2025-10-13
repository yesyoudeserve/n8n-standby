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

# Baixar bootstrap.sh novamente para o diretório correto
REPO_URL="https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main"
curl -sSL "${REPO_URL}/bootstrap.sh" -o bootstrap.sh

echo -e "${GREEN}✓ Sistema baixado${NC}"

echo -e "${BLUE}🔧 Executando instalação...${NC}"

# Baixar install.sh se não existir
if [ ! -f "install.sh" ]; then
    curl -sSL "${REPO_URL}/install.sh" -o install.sh
fi

./install.sh

echo -e "${BLUE}⚙️  Executando configuração interativa...${NC}"
./lib/setup.sh interactive

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    BOOTSTRAP CONCLUÍDO! 🎉             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "🎯 Sistema totalmente configurado e pronto!"
echo ""
echo "📋 Comandos disponíveis:"
echo ""
echo "   ./n8n-backup.sh backup     # Fazer backup"
echo "   ./n8n-backup.sh restore    # Restaurar dados"
echo "   ./n8n-backup.sh status     # Ver status"
echo "   ./n8n-backup.sh recovery   # Disaster recovery"
echo ""
echo "💡 O sistema detecta automaticamente o modo de operação!"
echo ""
