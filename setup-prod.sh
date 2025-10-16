#!/bin/bash
# ============================================
# Setup VM de Produção
# Instala dependências e configura backups automáticos
# ============================================

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SETUP VM DE PRODUÇÃO - N8N Backup    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Execute como root: sudo $0${NC}"
    exit 1
fi

# Detectar usuário original
ORIGINAL_USER=${SUDO_USER:-$USER}
if [ "$ORIGINAL_USER" = "root" ]; then
    echo -e "${YELLOW}⚠️  Detectado usuário root. Digite o usuário não-root:${NC}"
    read -p "> " ORIGINAL_USER
fi

echo -e "${BLUE}[1/7]${NC} Atualizando sistema..."
apt-get update -qq

echo -e "${BLUE}[2/7]${NC} Instalando dependências..."
apt-get install -y \
    curl \
    wget \
    jq \
    gzip \
    tar \
    postgresql-client \
    redis-tools \
    ufw \
    unzip \
    bc > /dev/null 2>&1

echo -e "${GREEN}✓ Dependências instaladas${NC}"

echo -e "${BLUE}[3/7]${NC} Instalando rclone..."
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash > /dev/null 2>&1
    echo -e "${GREEN}✓ Rclone instalado${NC}"
else
    echo -e "${YELLOW}⚠️  Rclone já instalado${NC}"
fi

echo -e "${BLUE}[4/7]${NC} Criando estrutura de diretórios..."
mkdir -p /opt/n8n-backup/{backups/local,logs,lib}
chown -R $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-backup
echo -e "${GREEN}✓ Diretórios criados${NC}"

echo -e "${BLUE}[5/7]${NC} Configurando cron para backup a cada 3 horas..."
CRON_JOB="0 */3 * * * /opt/n8n-backup/backup-prod.sh >> /opt/n8n-backup/logs/cron.log 2>&1"

if sudo -u $ORIGINAL_USER crontab -l 2>/dev/null | grep -q "backup-prod.sh"; then
    echo -e "${YELLOW}⚠️  Cron job já existe${NC}"
else
    (sudo -u $ORIGINAL_USER crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo -u $ORIGINAL_USER crontab -
    echo -e "${GREEN}✓ Backup automático configurado (a cada 3 horas)${NC}"
fi

echo -e "${BLUE}[6/7]${NC} Configurando firewall (UFW)..."
ufw --force enable > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw allow 3000/tcp > /dev/null 2>&1
ufw allow 5678/tcp > /dev/null 2>&1
ufw reload > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configurado${NC}"

echo -e "${BLUE}[7/7]${NC} Copiando scripts para /opt/n8n-backup..."
cp "${SCRIPT_DIR}"/*.sh /opt/n8n-backup/ 2>/dev/null || true
cp -r "${SCRIPT_DIR}"/lib/*.sh /opt/n8n-backup/lib/ 2>/dev/null || true
chmod +x /opt/n8n-backup/*.sh
chmod +x /opt/n8n-backup/lib/*.sh
chown -R $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-backup
echo -e "${GREEN}✓ Scripts copiados${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      INSTALAÇÃO CONCLUÍDA! 🎉          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Próximos Passos:${NC}"
echo ""
echo -e "${YELLOW}1️⃣  Configurar credenciais (como usuário normal):${NC}"
echo "   cd /opt/n8n-backup"
echo "   ./lib/setup.sh interactive"
echo ""
echo -e "${YELLOW}2️⃣  Fazer primeiro backup de teste:${NC}"
echo "   sudo ./backup-prod.sh"
echo ""
echo -e "${BLUE}📚 Backup automático está configurado!${NC}"
echo "   • Frequência: A cada 3 horas"
echo "   • Logs: tail -f /opt/n8n-backup/logs/cron.log"
echo "   • Retenção: 7 dias (remoto)"
echo ""