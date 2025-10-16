#!/bin/bash
# ============================================
# Setup VM Standby N8N - INSTALAÇÃO COMPLETA
# Baseado no install.sh do sistema principal
# ============================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║  N8N Standby VM - Setup Completo       ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./setup-standby.sh"
    exit 1
fi

# Obter usuário original
ORIGINAL_USER=${SUDO_USER:-$USER}

echo -e "${BLUE}[1/10]${NC} Atualizando sistema..."
apt update -qq && apt upgrade -y -qq
echo -e "${GREEN}✓ Sistema atualizado${NC}"

echo -e "${BLUE}[2/10]${NC} Instalando dependências completas..."
apt install -y postgresql-client jq pv dialog gzip pigz rclone git curl wget openssl ufw > /dev/null 2>&1
echo -e "${GREEN}✓ Dependências instaladas${NC}"

echo -e "${BLUE}[3/10]${NC} Criando estrutura de diretórios..."
mkdir -p /opt/n8n-standby/{lib,backups/local,logs}
chown -R $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-standby

# Criar arquivo de log vazio para evitar erro no logger
touch /opt/n8n-standby/logs/backup.log
chown $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-standby/logs/backup.log

echo -e "${GREEN}✓ Diretórios criados${NC}"

echo -e "${BLUE}[4/10]${NC} Instalando Docker..."

# Verificar se Docker já está instalado
if command -v docker > /dev/null 2>&1; then
    echo -e "${YELLOW}Docker já instalado, pulando...${NC}"
else
    curl -fsSL https://get.docker.com | sh
fi

# Garantir que Docker está rodando
systemctl enable docker 2>/dev/null || true
systemctl start docker 2>/dev/null || true

# Aguardar Docker iniciar
echo -e "${YELLOW}Aguardando Docker iniciar...${NC}"
sleep 5

# Testar Docker
if docker ps > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker instalado e funcionando${NC}"
else
    echo -e "${RED}✗ Docker não está funcionando${NC}"
    echo "Verifique: systemctl status docker"
    exit 1
fi

echo -e "${BLUE}[5/10]${NC} Instalando Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo -e "${GREEN}✓ Docker Compose instalado${NC}"

echo -e "${BLUE}[6/10]${NC} Instalando Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs -qq
echo -e "${GREEN}✓ Node.js instalado${NC}"

echo -e "${BLUE}[7/10]${NC} Instalando rclone..."
# Verificar se rclone já está instalado
if command -v rclone > /dev/null 2>&1; then
    echo -e "${YELLOW}rclone já instalado, pulando...${NC}"
else
    curl -fsSL https://rclone.org/install.sh | bash
fi
echo -e "${GREEN}✓ rclone instalado${NC}"

echo -e "${BLUE}[8/10]${NC} Configurando firewall (UFW)..."

# Habilitar UFW se não estiver ativo
sudo ufw --force enable

# Regras essenciais para N8N/EasyPanel
sudo ufw allow ssh                    # 22 - SSH
sudo ufw allow 80/tcp                 # 80 - HTTP N8N
sudo ufw allow 443/tcp                # 443 - HTTPS N8N
sudo ufw allow 3000/tcp               # 3000 - EasyPanel
sudo ufw allow 4000/tcp               # 4000 - PgAdmin
sudo ufw allow 5678/tcp               # 5678 - N8N Web Interface
sudo ufw allow 5289/tcp               # 5289 - N8N 2
sudo ufw allow 8080/tcp               # 8080 - Evolution API

# Recarregar regras
sudo ufw reload

echo -e "${GREEN}✓ Firewall configurado com portas essenciais${NC}"

echo -e "${BLUE}[9/10]${NC} Instalando EasyPanel..."

# Verificar se EasyPanel já está instalado
if docker ps -a --format 'table {{.Names}}' | grep -q easypanel; then
    echo -e "${YELLOW}EasyPanel já instalado, pulando...${NC}"
else
    # Verificar se há rate limit do Docker Hub
    if docker pull hello-world 2>&1 | grep -q "toomanyrequests"; then
        echo -e "${YELLOW}⚠️  Rate limit do Docker Hub detectado!${NC}"
        echo -e "${BLUE}💡 Soluções recomendadas:${NC}"
        echo ""
        echo -e "${YELLOW}1️⃣  Fazer login no Docker Hub:${NC}"
        echo "   docker login"
        echo ""
        echo -e "${YELLOW}2️⃣  Ou criar conta gratuita no Docker Hub:${NC}"
        echo "   https://hub.docker.com/signup"
        echo ""
        echo -e "${YELLOW}3️⃣  Ou aguardar 6 horas para reset do limite${NC}"
        echo ""
        echo -e "${RED}Instalação interrompida. Execute novamente após resolver o rate limit.${NC}"
        exit 1
    fi

    # Tentar instalar com retry em caso de outros erros
    retry_count=0
    max_retries=3

    while [ $retry_count -lt $max_retries ]; do
        if curl -fsSL https://get.easypanel.io | bash; then
            echo -e "${GREEN}✓ EasyPanel instalado${NC}"
            break
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo -e "${YELLOW}Tentativa $retry_count falhou, tentando novamente em 30s...${NC}"
                sleep 30
            else
                echo -e "${RED}✗ Falha na instalação do EasyPanel após $max_retries tentativas${NC}"
                echo -e "${YELLOW}Você pode tentar instalar manualmente depois:${NC}"
                echo "  curl -fsSL https://get.easypanel.io | bash"
                exit 1
            fi
        fi
    done
fi

# Aguardar EasyPanel iniciar
echo -e "${YELLOW}Aguardando EasyPanel iniciar...${NC}"
sleep 10

echo -e "${GREEN}✓ EasyPanel instalado${NC}"

echo -e "${BLUE}[10/10]${NC} Detectando credenciais automaticamente..."

# Detectar containers N8N
N8N_CONTAINER=$(docker ps --filter "name=n8n" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
if [ -n "$N8N_CONTAINER" ]; then
    DETECTED_N8N_KEY=$(docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
    if [ -n "$DETECTED_N8N_KEY" ]; then
        echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY detectada do container: ${N8N_CONTAINER}${NC}"
        # Salvar no config.env se existir
        if [ -f "/opt/n8n-standby/config.env" ]; then
            sed -i "s|N8N_ENCRYPTION_KEY=\"ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL\"|N8N_ENCRYPTION_KEY=\"${DETECTED_N8N_KEY}\"|" /opt/n8n-standby/config.env
        fi
    fi
fi

# Detectar PostgreSQL
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "postgres" | head -1 || echo "")
if [ -n "$POSTGRES_CONTAINER" ]; then
    DETECTED_POSTGRES_PASS=$(docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
    if [ -n "$DETECTED_POSTGRES_PASS" ]; then
        echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD detectada do container: ${POSTGRES_CONTAINER}${NC}"
        # Salvar no config.env se existir
        if [ -f "/opt/n8n-standby/config.env" ]; then
            sed -i "s|N8N_POSTGRES_PASSWORD=\"ALTERAR_COM_SUA_SENHA_POSTGRES_REAL\"|N8N_POSTGRES_PASSWORD=\"${DETECTED_POSTGRES_PASS}\"|" /opt/n8n-standby/config.env
        fi
    fi
fi

echo -e "${GREEN}✓ Detecção automática concluída${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   VM STANDBY TOTALMENTE PRONTA! 🎉     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASSOS:${NC}"
echo ""
echo -e "${YELLOW}1️⃣  Configurar credenciais:${NC}"
echo "   ./setup-credentials.sh  # Carrega do Supabase"
echo ""
echo -e "${YELLOW}2️⃣  Testar configuração:${NC}"
echo "   ./sync-standby.sh --test"
echo ""
echo -e "${YELLOW}3️⃣  Quando virar produção:${NC}"
echo "   sudo ./backup-production.sh --enable-cron"
echo "   sudo ./backup-production.sh  # Backup inicial"
echo ""
echo -e "${YELLOW}4️⃣  Para recuperação de desastre:${NC}"
echo "   sudo ./sync-standby.sh"
echo "   sudo ./restore-standby.sh"
echo ""
echo -e "${BLUE}🌐 Acesso:${NC}"
echo "   EasyPanel: http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   • VM pronta para ambos os modos (standby/produção)"
echo "   • Credenciais detectadas automaticamente"
echo "   • Firewall configurado com todas as portas"
echo "   • EasyPanel instalado e funcionando"
echo ""
