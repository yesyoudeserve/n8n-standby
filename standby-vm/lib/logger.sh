#!/bin/bash
# ============================================
# Sistema de Logs
# Arquivo: /opt/n8n-standby/lib/logger.sh
# ============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Definir LOG_FILE se não estiver definido
    LOG_FILE="${LOG_FILE:-/opt/n8n-standby/logs/backup.log}"

    # Escrever no arquivo de log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"

    # Exibir no terminal com cor
    case $level in
        INFO)
            echo -e "${BLUE}ℹ ${message}${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✓ ${message}${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}⚠ ${message}${NC}"
            ;;
        ERROR)
            echo -e "${RED}✗ ${message}${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

log_warning() {
    log "WARNING" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Função para exibir progresso
show_progress() {
    local message="$1"
    echo -ne "${BLUE}⏳ ${message}...${NC}\r"
}

clear_progress() {
    echo -ne "\r\033[K"
}

# Função para perguntar confirmação
confirm() {
    local message="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        local prompt="[S/n]"
        local default_answer="s"
    else
        local prompt="[s/N]"
        local default_answer="n"
    fi

    echo -ne "${YELLOW}❓ ${message} ${prompt}: ${NC}"
    read -r answer
    answer=${answer:-$default_answer}

    [[ "$answer" =~ ^[SsYy]$ ]]
}

# Verificar se comando existe
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando '$cmd' não encontrado. Instale antes de continuar."
        return 1
    fi
    return 0
}

# Verificar espaço em disco
check_disk_space() {
    local required_mb=$1
    local path=${2:-.}

    local available_mb=$(df -m "$path" | awk 'NR==2 {print $4}')

    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Espaço insuficiente. Necessário: ${required_mb}MB, Disponível: ${available_mb}MB"
        return 1
    fi

    return 0
}

# Formatação de tamanho de arquivo
format_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}")GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB"
    else
        echo "${bytes}B"
    fi
}

# Banner bonito
show_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════╗"
    echo "║    N8N Standby VM System                ║"
    echo "║           User Friendly v1.0          ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"
}
