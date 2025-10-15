#!/bin/bash
# ============================================
# Bootstrap VM Standby N8N
# Download e configuração automática
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
echo "║    N8N Standby VM Bootstrap            ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BLUE}📦 Baixando sistema de VM Standby...${NC}"

# Criar diretório
sudo mkdir -p /opt/n8n-standby
sudo chown $USER:$USER /opt/n8n-standby
cd /opt/n8n-standby

# Baixar arquivos do standby-vm
REPO_URL="https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/standby-vm"

echo "Baixando arquivos do sistema standby..."
curl -sSL "${REPO_URL}/README.md" -o README.md
curl -sSL "${REPO_URL}/setup-standby.sh" -o setup-standby.sh
curl -sSL "${REPO_URL}/sync-standby.sh" -o sync-standby.sh
curl -sSL "${REPO_URL}/backup-production.sh" -o backup-production.sh
curl -sSL "${REPO_URL}/config.env.template" -o config.env.template

echo -e "${GREEN}✓ Sistema baixado${NC}"

echo -e "${BLUE}🔧 Configurando permissões...${NC}"
chmod +x setup-standby.sh sync-standby.sh backup-production.sh
echo -e "${GREEN}✓ Permissões configuradas${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   BOOTSTRAP CONCLUÍDO! 🎉              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Próximos Passos:${NC}"
echo ""
echo -e "${YELLOW}1️⃣  Executar configuração completa:${NC}"
echo "   sudo ./setup-standby.sh"
echo ""
echo -e "${YELLOW}2️⃣  Ou configurar manualmente:${NC}"
echo "   cp config.env.template config.env"
echo "   nano config.env  # Editar credenciais"
echo "   sudo ./setup-standby.sh"
echo ""
echo -e "${BLUE}📖 Documentação: README.md${NC}"
echo ""
