#!/bin/bash
# ============================================
# Setup VM de Backup
# Instala EasyPanel + dependências
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
echo -e "${BLUE}║    SETUP VM DE BACKUP - N8N Backup     ║${NC}"
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

echo -e "${BLUE}[1/6]${NC} Atualizando sistema..."
apt-get update -qq

echo -e "${BLUE}[2/6]${NC} Instalando dependências..."
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

echo -e "${BLUE}[3/6]${NC} Instalando rclone..."
if ! command -v rclone &> /dev/null; then
    curl https://rclone.org/install.sh | bash > /dev/null 2>&1
    echo -e "${GREEN}✓ Rclone instalado${NC}"
else
    echo -e "${YELLOW}⚠️  Rclone já instalado${NC}"
fi

echo -e "${BLUE}[4/6]${NC} Instalando EasyPanel..."
if ! command -v easypanel &> /dev/null; then
    # Verificar se porta 80 já está em uso
    if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo -e "${YELLOW}⚠️  Porta 80 já em uso. Verificando se é EasyPanel...${NC}"
        
        # Verificar se é container EasyPanel
        if sudo docker ps --format "{{.Names}}" | grep -q "easypanel"; then
            echo -e "${GREEN}✓ EasyPanel já está instalado e rodando${NC}"
        else
            echo -e "${YELLOW}⚠️  Porta 80 ocupada por outro serviço${NC}"
            echo -e "${YELLOW}   Verifique: sudo lsof -i :80${NC}"
            echo -e "${YELLOW}   EasyPanel precisa da porta 80 livre${NC}"
            echo ""
            read -p "Continuar mesmo assim? (s/N): " continue_anyway
            if [ "$continue_anyway" != "s" ] && [ "$continue_anyway" != "S" ]; then
                echo "Setup cancelado"
                exit 1
            fi
        fi
    else
        # Porta livre, instalar EasyPanel
        curl -sSL https://get.easypanel.io | sh
        echo -e "${GREEN}✓ EasyPanel instalado${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANTE: Após este script, acesse EasyPanel em:${NC}"
        echo -e "${YELLOW}   https://$(curl -s ifconfig.me):3000${NC}"
        echo -e "${YELLOW}   Configure usuário e senha${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠️  EasyPanel já instalado${NC}"
    
    # Verificar se está rodando
    if sudo docker ps --format "{{.Names}}" | grep -q "easypanel"; then
        echo -e "${GREEN}✓ EasyPanel está rodando${NC}"
    else
        echo -e "${YELLOW}⚠️  EasyPanel instalado mas não está rodando${NC}"
        echo -e "${YELLOW}   Tente: sudo docker start \$(sudo docker ps -aq --filter name=easypanel)${NC}"
    fi
fi

echo -e "${BLUE}[5/6]${NC} Criando estrutura de diretórios..."
mkdir -p /opt/n8n-backup/{backups/local,logs,lib,schemas}
chown -R $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-backup
echo -e "${GREEN}✓ Diretórios criados${NC}"

echo -e "${BLUE}[6/6]${NC} Configurando firewall..."
ufw --force enable > /dev/null 2>&1
ufw allow ssh > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw allow 3000/tcp > /dev/null 2>&1
ufw allow 5678/tcp > /dev/null 2>&1
ufw reload > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configurado${NC}"

echo -e "${BLUE}[+]${NC} Copiando scripts..."
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
echo -e "${YELLOW}1️⃣  Configurar EasyPanel:${NC}"
echo "   • Acesse: https://$(curl -s ifconfig.me):3000"
echo "   • Crie usuário e senha"
echo ""
echo -e "${YELLOW}2️⃣  Importar schema dos serviços (MANUALMENTE):${NC}"
echo "   • No EasyPanel, importe o schema dos containers"
echo "   • Arquivo: Deve estar em /opt/n8n-backup/schemas/"
echo ""
echo -e "${YELLOW}3️⃣  Configurar credenciais (como usuário normal):${NC}"
echo "   cd /opt/n8n-backup"
echo "   ./lib/setup.sh interactive"
echo ""
echo -e "${YELLOW}4️⃣  Restaurar último backup:${NC}"
echo "   sudo ./restore-backup.sh"
echo ""
echo -e "${BLUE}💡 Dica: Esta VM ficará desligada e só será ativada em caso de DR${NC}"
echo ""