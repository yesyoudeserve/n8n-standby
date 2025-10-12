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

# Aqui você substituiria por git clone do seu repositório
# Por enquanto, assumindo que os arquivos já estão no diretório

echo -e "${GREEN}✓ Sistema baixado${NC}"

echo -e "${BLUE}🔧 Executando instalação...${NC}"
./install.sh

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    BOOTSTRAP CONCLUÍDO! 🎉             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1️⃣  Configurar rclone (se ainda não tem):"
echo "   cp /caminho/para/rclone.conf ~/.config/rclone/rclone.conf"
echo ""
echo "2️⃣  Executar recuperação:"
echo "   ./n8n-backup.sh recovery"
echo ""
echo "3️⃣  Ou verificar status:"
echo "   ./n8n-backup.sh status"
echo ""
