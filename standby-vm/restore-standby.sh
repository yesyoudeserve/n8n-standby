#!/bin/bash
# ============================================
# Restore VM Standby N8N
# Restauração do banco de dados na VM Standby
# ============================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Diretório do script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações se existir
if [ -f "${SCRIPT_DIR}/config.env" ]; then
    source "${SCRIPT_DIR}/config.env"
fi

# Carregar bibliotecas do projeto principal
if [ -f "${SCRIPT_DIR}/../lib/logger.sh" ]; then
    source "${SCRIPT_DIR}/../lib/logger.sh"
    source "${SCRIPT_DIR}/../lib/security.sh"
    source "${SCRIPT_DIR}/../lib/postgres.sh"
fi

echo -e "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║    N8N Standby VM Restore              ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Execute com sudo!${NC}"
    echo "   sudo ./restore-standby.sh"
    exit 1
fi

echo -e "${BLUE}[1/4]${NC} Verificando sincronização..."

# Verificar se backups existem
BACKUP_LOCAL_DIR="${SCRIPT_DIR}/backups"
if [ ! -d "$BACKUP_LOCAL_DIR" ] || [ -z "$(ls -A "$BACKUP_LOCAL_DIR" 2>/dev/null)" ]; then
    echo -e "${RED}✗ Nenhum backup encontrado!${NC}"
    echo "   Execute primeiro: sudo ./sync-standby.sh"
    exit 1
fi

# Encontrar backup mais recente baixado
LATEST_BACKUP_FILE=$(ls -t "${BACKUP_LOCAL_DIR}"/n8n_backup_*.tar.gz 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP_FILE" ]; then
    echo -e "${RED}✗ Arquivo de backup não encontrado!${NC}"
    exit 1
fi

LATEST_BACKUP_NAME=$(basename "$LATEST_BACKUP_FILE")
echo -e "${GREEN}✓ Backup encontrado: ${LATEST_BACKUP_NAME}${NC}"

echo -e "${BLUE}[2/4]${NC} Preparando restauração..."

# Criar diretório temporário
TEMP_DIR=$(mktemp -d)

# Extrair backup
tar -xzf "$LATEST_BACKUP_FILE" -C "$TEMP_DIR"

# Verificar se tem dump SQL
DUMP_FILE=$(find "$TEMP_DIR" -name "n8n_dump.sql.gz" | head -1)
if [ -z "$DUMP_FILE" ]; then
    echo -e "${RED}✗ Dump SQL não encontrado no backup!${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Arquivos de backup OK${NC}"

echo -e "${BLUE}[3/4]${NC} Restaurando banco de dados..."

# Verificar se PostgreSQL está rodando
if ! docker ps --format "{{.Names}}" | grep -q postgres; then
    echo -e "${RED}✗ PostgreSQL não está rodando!${NC}"
    echo "   Verifique se o EasyPanel está funcionando"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Limpar banco atual (com confirmação)
echo -e "${YELLOW}⚠️  ATENÇÃO: Isso irá limpar o banco atual!${NC}"
read -p "Continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Cancelado pelo usuário"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Limpar e restaurar banco
POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -1)

echo -e "${YELLOW}Limpando banco atual...${NC}"
docker exec "$POSTGRES_CONTAINER" psql -U n8n -d n8n -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true

echo -e "${YELLOW}Restaurando dados...${NC}"
gunzip < "$DUMP_FILE" | docker exec -i "$POSTGRES_CONTAINER" psql -U n8n -d n8n

echo -e "${GREEN}✓ Banco de dados restaurado${NC}"

echo -e "${BLUE}[4/4]${NC} Finalizando..."

# Limpar arquivos temporários
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    RESTAURAÇÃO CONCLUÍDA! 🎉          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📋 Status:${NC}"
echo "   • Banco PostgreSQL restaurado"
echo "   • Dados do backup: ${LATEST_BACKUP_NAME}"
echo ""
echo -e "${YELLOW}🚀 Próximos passos:${NC}"
echo "   1. Verificar N8N: http://$(hostname -I | awk '{print $1}'):5678"
echo "   2. Testar workflows e credenciais"
echo "   3. Redirecionar tráfego se necessário"
echo ""
echo -e "${RED}⚠️  IMPORTANTE:${NC}"
echo "   • Esta VM agora contém os dados de produção"
echo "   • Desligue a VM principal antiga"
echo "   • Configure backup automático nesta nova VM"
echo ""
