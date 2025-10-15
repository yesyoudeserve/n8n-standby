#!/bin/bash
# ============================================
# Setup VM Standby N8N
# Configuração inicial da VM Standby
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
echo "║    N8N Standby VM Setup                ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./setup-standby.sh"
    exit 1
fi

echo -e "${BLUE}[1/8]${NC} Atualizando sistema..."
apt update -qq && apt upgrade -y -qq
echo -e "${GREEN}✓ Sistema atualizado${NC}"

echo -e "${BLUE}[2/8]${NC} Instalando dependências básicas..."
apt install -y \
    curl \
    wget \
    git \
    jq \
    pv \
    dialog \
    gzip \
    openssl \
    lsof \
    ufw \
    -qq
echo -e "${GREEN}✓ Dependências básicas instaladas${NC}"

echo -e "${BLUE}[3/8]${NC} Instalando Docker..."
curl -fsSL https://get.docker.com | sh -s
systemctl enable docker
systemctl start docker
echo -e "${GREEN}✓ Docker instalado${NC}"

echo -e "${BLUE}[4/8]${NC} Instalando Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo -e "${GREEN}✓ Docker Compose instalado${NC}"

echo -e "${BLUE}[5/8]${NC} Instalando Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs -qq
echo -e "${GREEN}✓ Node.js instalado${NC}"

echo -e "${BLUE}[6/8]${NC} Instalando rclone..."
curl -fsSL https://rclone.org/install.sh | bash
echo -e "${GREEN}✓ rclone instalado${NC}"

echo -e "${BLUE}[7/8]${NC} Configurando firewall..."
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp
ufw allow 4000/tcp
ufw allow 5678/tcp
ufw allow 5289/tcp
ufw allow 8080/tcp
ufw reload
echo -e "${GREEN}✓ Firewall configurado${NC}"

echo -e "${BLUE}[8/8]${NC} Instalando EasyPanel..."
curl -fsSL https://get.easypanel.io | bash
echo -e "${GREEN}✓ EasyPanel instalado${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   VM STANDBY CONFIGURADA! 🎉           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Próximos Passos:${NC}"
echo ""
echo -e "${YELLOW}1️⃣  Configurar credenciais:${NC}"
echo "   cp config.env.template config.env"
echo "   nano config.env  # Editar credenciais"
echo ""
echo -e "${YELLOW}2️⃣  Testar configuração:${NC}"
echo "   ./sync-standby.sh --test"
echo ""
echo -e "${YELLOW}3️⃣  Desligar VM:${NC}"
echo "   sudo shutdown -h now"
echo ""
echo -e "${BLUE}🌐 Acesso:${NC}"
echo "   EasyPanel: http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   • Mantenha esta VM DESLIGADA"
echo "   • Ligue apenas em caso de emergência"
echo "   • Execute sync-standby.sh antes de usar"
echo ""
