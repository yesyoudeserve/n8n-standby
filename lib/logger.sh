#!/bin/bash
# ============================================
# Funções de Logging
# Arquivo: /opt/n8n-backup/lib/logger.sh
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Criar diretório de logs se não existir
mkdir -p "$(dirname "${LOG_FILE:-/opt/n8n-backup/logs/backup.log}")"

# Função de log genérica
log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE:-/opt/n8n-backup/logs/backup.log}"
}

# Log info
log_info() {
    echo -e "${BLUE}ℹ️  $@${NC}"
    log_message "INFO" "$@"
}

# Log success
log_success() {
    echo -e "${GREEN}✅ $@${NC}"
    log_message "SUCCESS" "$@"
}

# Log warning
log_warning() {
    echo -e "${YELLOW}⚠️  $@${NC}"
    log_message "WARNING" "$@"
}

# Log error
log_error() {
    echo -e "${RED}❌ $@${NC}"
    log_message "ERROR" "$@"
}

# Verificar se comando existe
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar espaço em disco
check_disk_space() {
    local required_mb=$1
    local path=$2
    
    local available_mb=$(df -m "$path" | tail -1 | awk '{print $4}')
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Espaço insuficiente. Necessário: ${required_mb}MB, Disponível: ${available_mb}MB"
        return 1
    fi
    
    return 0
}

# Banner
show_banner() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        N8N Backup System v2.0          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}