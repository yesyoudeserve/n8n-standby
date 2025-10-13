#!/bin/bash
# ============================================
# Instalador do Sistema de Backup N8N
# Arquivo: install.sh
# Execute: sudo ./install.sh
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
echo "║  Instalador N8N Backup System v1.0    ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./install.sh"
    exit 1
fi

# Obter usuário original
ORIGINAL_USER=${SUDO_USER:-$USER}

echo -e "${BLUE}[1/6]${NC} Instalando dependências..."
apt update -qq
apt install -y postgresql-client jq pv dialog gzip pigz rclone git curl wget openssl > /dev/null 2>&1
echo -e "${GREEN}✓ Dependências instaladas${NC}"

echo -e "${BLUE}[2/6]${NC} Criando estrutura de diretórios..."
mkdir -p /opt/n8n-backup/{lib,backups/local,logs}
chown -R $ORIGINAL_USER:$ORIGINAL_USER /opt/n8n-backup
echo -e "${GREEN}✓ Diretórios criados${NC}"

echo -e "${BLUE}[3/6]${NC} Configurando permissões..."
chmod +x /opt/n8n-backup/{backup.sh,restore.sh,n8n-backup.sh,backup-easypanel-schema.sh}
chmod +x /opt/n8n-backup/lib/*.sh
echo -e "${GREEN}✓ Permissões configuradas${NC}"

echo -e "${BLUE}[4/6]${NC} Detectando credenciais automaticamente..."

# Detectar containers N8N
N8N_CONTAINER=$(docker ps --filter "name=n8n" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
if [ -n "$N8N_CONTAINER" ]; then
    DETECTED_N8N_KEY=$(docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
    if [ -n "$DETECTED_N8N_KEY" ]; then
        echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY detectada do container: ${N8N_CONTAINER}${NC}"
        # Atualizar config.env (usando | como delimitador para evitar problemas com /)
        sed -i "s|N8N_ENCRYPTION_KEY=\"ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL\"|N8N_ENCRYPTION_KEY=\"${DETECTED_N8N_KEY}\"|" /opt/n8n-backup/config.env
    fi
fi

# Detectar PostgreSQL
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "postgres" | head -1 || echo "")
if [ -n "$POSTGRES_CONTAINER" ]; then
    DETECTED_POSTGRES_PASS=$(docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
    if [ -n "$DETECTED_POSTGRES_PASS" ]; then
        echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD detectada do container: ${POSTGRES_CONTAINER}${NC}"
        # Atualizar config.env
        sed -i "s/N8N_POSTGRES_PASSWORD=\"ALTERAR_COM_SUA_SENHA_POSTGRES_REAL\"/N8N_POSTGRES_PASSWORD=\"${DETECTED_POSTGRES_PASS}\"/" /opt/n8n-backup/config.env
    fi
fi

echo -e "${BLUE}[5/6]${NC} Configurando backup automático (cron)..."

# Criar entrada no crontab para o usuário original
CRON_JOB="0 3 * * * /opt/n8n-backup/backup.sh >> /opt/n8n-backup/logs/cron.log 2>&1"

# Verificar se já existe
if sudo -u $ORIGINAL_USER crontab -l 2>/dev/null | grep -q "n8n-backup"; then
    echo -e "${YELLOW}⚠ Cron job já existe${NC}"
else
    (sudo -u $ORIGINAL_USER crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo -u $ORIGINAL_USER crontab -
    echo -e "${GREEN}✓ Backup automático configurado (diariamente às 3h AM)${NC}"
fi

echo -e "${BLUE}[6/6]${NC} Configurando monitoramento..."
su - $ORIGINAL_USER -c "/opt/n8n-backup/lib/monitoring.sh setup" 2>/dev/null || true
echo -e "${GREEN}✓ Monitoramento configurado${NC}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      INSTALAÇÃO CONCLUÍDA! 🎉          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1️⃣  Configurar credenciais (como usuário normal):"
echo "   cd /opt/n8n-backup"
echo "   ./lib/setup.sh interactive"
echo ""
echo "2️⃣  Após configurar, fazer primeiro backup:"
echo "   sudo ./n8n-backup.sh backup"
echo ""
echo "⚠️  IMPORTANTE:"
echo "   - Execute o setup.sh SEM sudo (como usuário normal)"
echo "   - O setup irá pedir todas as credenciais interativamente"
echo ""