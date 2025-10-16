#!/bin/bash
# ============================================
# Script de Restauração VM de Backup
# Baixa e restaura último backup disponível
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"

# Variáveis
RESTORE_DIR="${BACKUP_LOCAL_DIR}/restore"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Enviar notificação Discord
send_discord() {
    local message=$1
    local level=${2:-"info"}
    
    if [ -z "$NOTIFY_WEBHOOK" ]; then
        return 0
    fi
    
    local color="3447003"
    case $level in
        warning) color="16776960" ;;
        error) color="15158332" ;;
        success) color="3066993" ;;
    esac
    
    local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "N8N Restore - Backup VM",
    "description": "$message",
    "color": $color,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "footer": {"text": "$(hostname)"}
  }]
}
EOF
)
    
    curl -H "Content-Type: application/json" -d "$payload" "$NOTIFY_WEBHOOK" --silent > /dev/null 2>&1 || true
}

# Detectar comando docker
detect_docker_cmd() {
    if docker ps > /dev/null 2>&1; then
        echo "docker"
    elif sudo docker ps > /dev/null 2>&1; then
        echo "sudo docker"
    else
        log_error "Docker não acessível"
        exit 1
    fi
}

# Detectar container PostgreSQL (com suporte a sufixos)
detect_postgres_container() {
    local DOCKER_CMD=$(detect_docker_cmd)
    
    # Buscar container que contenha "postgres" no nome
    local container=$($DOCKER_CMD ps --format "{{.Names}}" | grep -i "postgres" | grep -v "pgadmin\|pgweb" | head -1)
    
    if [ -z "$container" ]; then
        log_error "Container PostgreSQL não encontrado"
        $DOCKER_CMD ps --format "table {{.Names}}\t{{.Image}}"
        return 1
    fi
    
    echo "$container"
}

# Detectar container Redis (com suporte a sufixos)
detect_redis_container() {
    local DOCKER_CMD=$(detect_docker_cmd)
    
    # Buscar container que contenha "redis" no nome
    local container=$($DOCKER_CMD ps --format "{{.Names}}" | grep -i "redis" | head -1)
    
    if [ -z "$container" ]; then
        log_warning "Container Redis não encontrado"
        return 1
    fi
    
    echo "$container"
}

# Detectar todos containers N8N
detect_n8n_containers() {
    local DOCKER_CMD=$(detect_docker_cmd)
    
    # Buscar todos containers com "n8n" no nome (exceto postgres/redis)
    $DOCKER_CMD ps --format "{{.Names}}" | grep -i "n8n" | grep -v "postgres\|redis\|pgadmin\|pgweb"
}

# Listar backups disponíveis
list_available_backups() {
    log_info "📋 Listando backups disponíveis..."
    
    echo ""
    echo "=== ORACLE BACKUPS ==="
    if [ "$ORACLE_ENABLED" = "true" ]; then
        rclone lsl "oracle:${ORACLE_BUCKET}/" --include "n8n_backup_*.tar.gz" | tail -5 || echo "Nenhum backup encontrado"
    fi
    
    echo ""
    echo "=== B2 BACKUPS ==="
    if [ "$B2_ENABLED" = "true" ]; then
        rclone lsl "b2:${B2_BUCKET}/" --include "n8n_backup_*.tar.gz" | tail -5 || echo "Nenhum backup encontrado"
    fi
    echo ""
}

# Obter último backup
get_latest_backup() {
    local storage=$1
    local bucket=$2
    
    local latest=$(rclone lsl "${storage}:${bucket}/" --include "n8n_backup_*.tar.gz" 2>/dev/null | \
        tail -1 | awk '{print $NF}')
    
    echo "$latest"
}

# Baixar backup
download_backup() {
    local storage=$1
    local bucket=$2
    local filename=$3
    
    log_info "📥 Baixando backup: $filename"
    
    mkdir -p "$RESTORE_DIR"
    
    if rclone copy "${storage}:${bucket}/${filename}" "$RESTORE_DIR/" --progress; then
        log_success "Download concluído"
        echo "${RESTORE_DIR}/${filename}"
        return 0
    else
        log_error "Falha no download"
        return 1
    fi
}

# Extrair backup
extract_backup() {
    local backup_file=$1
    
    log_info "📦 Extraindo backup..."
    
    local extract_dir="${RESTORE_DIR}/extracted"
    mkdir -p "$extract_dir"
    
    tar -xzf "$backup_file" -C "$extract_dir"
    
    # Encontrar o diretório extraído
    local backup_folder=$(find "$extract_dir" -maxdepth 1 -type d -name "n8n_backup_*" | head -1)
    
    if [ -d "$backup_folder" ]; then
        log_success "Backup extraído em: $backup_folder"
        echo "$backup_folder"
        return 0
    else
        log_error "Falha ao extrair backup"
        return 1
    fi
}

# Restaurar PostgreSQL
restore_postgresql() {
    local backup_folder=$1
    local DOCKER_CMD=$(detect_docker_cmd)
    
    log_info "🗄️  Restaurando PostgreSQL..."
    
    local dump_file="${backup_folder}/postgresql_dump.sql.gz"
    
    if [ ! -f "$dump_file" ]; then
        log_error "Dump PostgreSQL não encontrado: $dump_file"
        return 1
    fi
    
    # Parar containers temporariamente
    log_info "Parando containers N8N..."
    $DOCKER_CMD stop $(docker ps -q --filter "name=n8n") 2>/dev/null || true
    
    # Limpar banco atual
    log_info "Limpando bancos existentes..."
    echo "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname NOT IN ('postgres', 'template0', 'template1');" | \
        $DOCKER_CMD exec -i n8n_postgres psql -U postgres > /dev/null 2>&1 || true
    
    echo "DROP DATABASE IF EXISTS n8n;" | \
        $DOCKER_CMD exec -i n8n_postgres psql -U postgres > /dev/null 2>&1 || true
    
    # Restaurar
    log_info "Restaurando dump..."
    gunzip -c "$dump_file" | $DOCKER_CMD exec -i n8n_postgres psql -U postgres > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "PostgreSQL restaurado com sucesso"
        
        # Reiniciar containers
        log_info "Reiniciando containers N8N..."
        $DOCKER_CMD start $(docker ps -aq --filter "name=n8n") 2>/dev/null || true
        sleep 5
        
        return 0
    else
        log_error "Falha ao restaurar PostgreSQL"
        return 1
    fi
}

# Restaurar Redis
restore_redis() {
    local backup_folder=$1
    local DOCKER_CMD=$(detect_docker_cmd)
    
    log_info "📦 Restaurando Redis..."
    
    local redis_file="${backup_folder}/redis_dump.rdb"
    
    if [ ! -f "$redis_file" ]; then
        log_warning "Dump Redis não encontrado (pode estar vazio)"
        return 0
    fi
    
    # Parar Redis
    $DOCKER_CMD stop n8n_redis 2>/dev/null || true
    
    # Copiar arquivo RDB
    $DOCKER_CMD cp "$redis_file" n8n_redis:/data/dump.rdb
    
    # Reiniciar Redis
    $DOCKER_CMD start n8n_redis
    sleep 3
    
    log_success "Redis restaurado com sucesso"
    return 0
}

# Menu interativo
interactive_restore() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   RESTAURAR BACKUP - VM DE BACKUP      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    list_available_backups
    
    echo ""
    echo "Escolha o storage:"
    echo "1) Oracle (último backup)"
    echo "2) B2 (último backup)"
    echo "3) Listar todos e escolher"
    echo "0) Cancelar"
    echo ""
    read -p "> " choice
    
    local storage=""
    local bucket=""
    local filename=""
    
    case $choice in
        1)
            storage="oracle"
            bucket="$ORACLE_BUCKET"
            filename=$(get_latest_backup "$storage" "$bucket")
            ;;
        2)
            storage="b2"
            bucket="$B2_BUCKET"
            filename=$(get_latest_backup "$storage" "$bucket")
            ;;
        3)
            echo "Feature em desenvolvimento"
            exit 0
            ;;
        0)
            echo "Cancelado"
            exit 0
            ;;
        *)
            echo "Opção inválida"
            exit 1
            ;;
    esac
    
    if [ -z "$filename" ]; then
        log_error "Nenhum backup encontrado"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}Backup selecionado: $filename${NC}"
    echo -e "${YELLOW}Storage: $storage${NC}"
    echo ""
    echo -e "${RED}⚠️  ATENÇÃO: Esta operação irá SUBSTITUIR todos os dados atuais!${NC}"
    echo ""
    read -p "Confirme digitando 'RESTAURAR': " confirm
    
    if [ "$confirm" != "RESTAURAR" ]; then
        echo "Cancelado"
        exit 0
    fi
    
    # Executar restauração
    send_discord "🚀 **Restauração Iniciada**\n\nBackup: $filename\nStorage: $storage" "info"
    
    local backup_file=$(download_backup "$storage" "$bucket" "$filename")
    
    if [ $? -ne 0 ]; then
        send_discord "❌ **Falha no download**" "error"
        exit 1
    fi
    
    local backup_folder=$(extract_backup "$backup_file")
    
    if [ $? -ne 0 ]; then
        send_discord "❌ **Falha na extração**" "error"
        exit 1
    fi
    
    # Restaurar PostgreSQL
    if ! restore_postgresql "$backup_folder"; then
        send_discord "❌ **Falha ao restaurar PostgreSQL**" "error"
        exit 1
    fi
    
    # Restaurar Redis
    restore_redis "$backup_folder"
    
    # Limpeza
    log_info "🧹 Limpando arquivos temporários..."
    rm -rf "$RESTORE_DIR"
    
    log_success "✅ Restauração concluída com sucesso!"
    send_discord "✅ **Restauração Concluída!**\n\nBackup: $filename\nVM de Backup está pronta para uso." "success"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     RESTAURAÇÃO CONCLUÍDA! 🎉          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📋 Status dos Containers:${NC}"
    docker ps --filter "name=n8n"
    echo ""
    echo -e "${YELLOW}💡 Acesse N8N em: http://$(curl -s ifconfig.me):5678${NC}"
    echo ""
}

# Main
main() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}❌ Execute como root: sudo $0${NC}"
        exit 1
    fi
    
    interactive_restore
}

trap 'log_error "Restauração falhou"; send_discord "❌ **Restauração falhou na linha $LINENO**" "error"; exit 1' ERR

main "$@"