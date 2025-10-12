#!/bin/bash
# ============================================
# Instalador do Sistema de Backup N8N
# Arquivo: install.sh
# Execute: curl -sSL https://raw.githubusercontent.com/SEU_USERNAME/SEU_REPO/main/install.sh | bash
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
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Não execute como root! Use um usuário normal.${NC}"
    exit 1
fi

echo -e "${BLUE}[1/7]${NC} Instalando dependências..."
sudo apt update -qq
sudo apt install -y postgresql-client jq pv dialog gzip pigz rclone git > /dev/null 2>&1
echo -e "${GREEN}✓ Dependências instaladas${NC}"

echo -e "${BLUE}[2/7]${NC} Criando estrutura de diretórios..."
sudo mkdir -p /opt/n8n-backup/{lib,backups/local,logs}
sudo chown -R $USER:$USER /opt/n8n-backup
echo -e "${GREEN}✓ Diretórios criados${NC}"

echo -e "${BLUE}[3/7]${NC} Baixando scripts..."
cd /opt/n8n-backup

# Você pode substituir isso por um git clone do seu repositório
# Por enquanto, vou criar os arquivos localmente
echo "Os scripts devem ser colocados manualmente nos seguintes locais:"
echo "  - /opt/n8n-backup/config.env"
echo "  - /opt/n8n-backup/backup.sh"
echo "  - /opt/n8n-backup/restore.sh"
echo "  - /opt/n8n-backup/lib/logger.sh"
echo "  - /opt/n8n-backup/lib/menu.sh"
echo "  - /opt/n8n-backup/lib/postgres.sh"

echo -e "${BLUE}[4/7]${NC} Configurando permissões..."
chmod +x /opt/n8n-backup/{backup.sh,restore.sh}
chmod +x /opt/n8n-backup/lib/*.sh
echo -e "${GREEN}✓ Permissões configuradas${NC}"

echo ""
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo -e "${YELLOW}    CONFIGURAÇÃO NECESSÁRIA${NC}"
echo -e "${YELLOW}════════════════════════════════════════${NC}"
echo ""
echo "Antes de continuar, você precisa configurar:"
echo ""
echo "1️⃣  Editar /opt/n8n-backup/config.env:"
echo "   - N8N_POSTGRES_PASSWORD"
echo "   - N8N_ENCRYPTION_KEY (CRÍTICO!)"
echo "   - ORACLE_NAMESPACE, ORACLE_BUCKET, ORACLE_COMPARTMENT_ID"
echo "   - B2_ACCOUNT_ID, B2_APPLICATION_KEY, B2_BUCKET"
echo ""
read -p "Pressione ENTER quando terminar a configuração..."

echo ""
echo -e "${BLUE}[5/7]${NC} Encontrando credenciais do N8N..."

# Tentar encontrar o encryption key automaticamente
ENCRYPTION_KEY=$(docker exec -it $(docker ps -q -f name=n8n-main) env | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' 2>/dev/null || echo "")

if [ -n "$ENCRYPTION_KEY" ]; then
    echo -e "${GREEN}✓ Encryption key encontrada!${NC}"
    echo "   Key: ${ENCRYPTION_KEY:0:20}..."
    echo ""
    echo "IMPORTANTE: Salve esta chave em um local seguro!"
    echo "Sem ela, não será possível restaurar as credenciais!"
    echo ""
    
    # Atualizar config.env automaticamente
    sed -i "s/N8N_ENCRYPTION_KEY=\"SUA_CHAVE_ENCRYPTION\"/N8N_ENCRYPTION_KEY=\"${ENCRYPTION_KEY}\"/" /opt/n8n-backup/config.env
else
    echo -e "${YELLOW}⚠ Encryption key não encontrada automaticamente${NC}"
    echo "   Configure manualmente no config.env"
fi

# Tentar encontrar senha do PostgreSQL
POSTGRES_PASSWORD=$(docker exec -it $(docker ps -q -f name=n8n-main) env | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' 2>/dev/null || echo "")

if [ -n "$POSTGRES_PASSWORD" ]; then
    echo -e "${GREEN}✓ Senha PostgreSQL encontrada!${NC}"
    sed -i "s/N8N_POSTGRES_PASSWORD=\"SUA_SENHA_POSTGRES\"/N8N_POSTGRES_PASSWORD=\"${POSTGRES_PASSWORD}\"/" /opt/n8n-backup/config.env
fi

echo -e "${BLUE}[6/7]${NC} Configurando backup automático (cron)..."

# Criar entrada no crontab
CRON_JOB="0 3 * * * /opt/n8n-backup/backup.sh >> /opt/n8n-backup/logs/cron.log 2>&1"

# Verificar se já existe
if crontab -l 2>/dev/null | grep -q "n8n-backup"; then
    echo -e "${YELLOW}⚠ Cron job já existe${NC}"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}✓ Backup automático configurado (diariamente às 3h AM)${NC}"
fi

echo -e "${BLUE}[7/7]${NC} Configurando monitoramento..."

# Configurar monitoramento automático
/opt/n8n-backup/lib/monitoring.sh setup

echo -e "${GREEN}✓ Monitoramento configurado${NC}"

echo -e "${BLUE}[7/7]${NC} Testando configuração..."

# Testar conexão PostgreSQL
if /opt/n8n-backup/backup.sh --test-connection 2>/dev/null; then
    echo -e "${GREEN}✓ Conexão com PostgreSQL OK${NC}"
else
    echo -e "${YELLOW}⚠ Não foi possível testar a conexão${NC}"
    echo "   Execute manualmente: /opt/n8n-backup/backup.sh --test-connection"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      INSTALAÇÃO CONCLUÍDA! 🎉          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Próximos passos:"
echo ""
echo "1️⃣  Fazer primeiro backup manual:"
echo "   sudo /opt/n8n-backup/backup.sh"
echo ""
echo "2️⃣  Para restaurar dados:"
echo "   sudo /opt/n8n-backup/restore.sh"
echo ""
echo "3️⃣  Verificar logs:"
echo "   tail -f /opt/n8n-backup/logs/backup.log"
echo ""
echo "4️⃣  Configurar Oracle e B2 no rclone:"
echo "   rclone config"
echo ""
echo "📁 Estrutura criada em: /opt/n8n-backup/"
echo "⏰ Backup automático: Todos os dias às 3h AM"
echo "💾 Retenção local: 2 dias | Remota: 7 dias"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   Salve o N8N_ENCRYPTION_KEY em local seguro!"
echo "   Sem ele, credenciais não poderão ser restauradas!"
echo ""
