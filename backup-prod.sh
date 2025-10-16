#!/bin/bash
# ============================================
# Script de Backup VM de Produção
# Executa backup completo de PostgreSQL e Redis
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"

# Variáveis
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
BACKUP_DIR="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}"
BACKUP_ARCHIVE="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}.tar.gz"

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
    "title": "N8N Backup - Produção",
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

# Detectar comando docker (com ou sem sudo)
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

# Backup PostgreSQL completo
backup_postgresql() {
    log_info "🗄️  Backup PostgreSQL..."
    
    local DOCKER_CMD=$(detect_docker_cmd)
    local POSTGRES_CONTAINER=$(detect_postgres_container)
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        return 1
    fi
    
    log_info "📦 Container detectado: $POSTGRES_CONTAINER"
    
    local dump_file="${BACKUP_DIR}/postgresql_dump.sql.gz"
    
    # Dump de TODOS os bancos
    $DOCKER_CMD exec -i "$POSTGRES_CONTAINER" pg_dumpall -U postgres | gzip > "$dump_file"
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$dump_file" | cut -f1)
        log_success "PostgreSQL backup concluído ($size)"
        return 0
    else
        log_error "Falha no backup PostgreSQL"
        return 1
    fi
}

# Backup Redis completo
backup_redis() {
    log_info "📦 Backup Redis..."
    
    local DOCKER_CMD=$(detect_docker_cmd)
    local REDIS_CONTAINER=$(detect_redis_container)
    
    if [ -z "$REDIS_CONTAINER" ]; then
        log_warning "Redis não encontrado, pulando backup"
        return 0
    fi
    
    log_info "📦 Container detectado: $REDIS_CONTAINER"
    
    local redis_file="${BACKUP_DIR}/redis_dump.rdb"
    
    # Copiar arquivo RDB diretamente (não precisa de SAVE pois Redis persiste automaticamente)
    log_info "Copiando dump.rdb..."
    if timeout 30 $DOCKER_CMD cp "$REDIS_CONTAINER:/data/dump.rdb" "$redis_file" 2>/dev/null; then
        if [ -f "$redis_file" ]; then
            local size=$(du -h "$redis_file" | cut -f1)
            log_success "Redis backup concluído ($size)"
            return 0
        else
            log_warning "Arquivo Redis não foi criado (não crítico)"
            return 0
        fi
    else
        log_warning "Falha ao copiar dump.rdb do Redis (não crítico)"
        return 0
    fi
}
    
    if [ -f "$redis_file" ]; then
        local size=$(du -h "$redis_file" | cut -f1)
        log_success "Redis backup concluído ($size)"
        return 0
    else
        log_warning "Redis backup não encontrado (pode estar vazio)"
        return 0
    fi
}

# Upload para Oracle
upload_to_oracle() {
    if [ "$ORACLE_ENABLED" != "true" ]; then
        return 0
    fi
    
    log_info "📤 Upload para Oracle..."
    
    if rclone copy "$BACKUP_ARCHIVE" "oracle:${ORACLE_BUCKET}/" --progress; then
        log_success "Upload Oracle concluído"
        send_discord "✅ **Upload Oracle OK**\n\nArquivo: $(basename $BACKUP_ARCHIVE)" "success"
    else
        log_error "Falha no upload Oracle"
        send_discord "❌ **Upload Oracle falhou**" "error"
    fi
}

# Upload para B2
upload_to_b2() {
    if [ "$B2_ENABLED" != "true" ]; then
        return 0
    fi
    
    log_info "📤 Upload para B2..."
    
    if rclone copy "$BACKUP_ARCHIVE" "b2:${B2_BUCKET}/" --progress; then
        log_success "Upload B2 concluído"
        send_discord "✅ **Upload B2 OK**\n\nArquivo: $(basename $BACKUP_ARCHIVE)" "success"
    else
        log_error "Falha no upload B2"
        send_discord "❌ **Upload B2 falhou**" "error"
    fi
}

# Limpeza de backups antigos
cleanup_old_backups() {
    log_info "🧹 Limpando backups antigos..."
    
    # Local (manter 2 dias)
    find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f -mtime +2 -delete 2>/dev/null || true
    
    # Oracle (manter 7 dias)
    if [ "$ORACLE_ENABLED" = "true" ]; then
        rclone delete "oracle:${ORACLE_BUCKET}/" \
            --min-age 7d \
            --include "n8n_backup_*.tar.gz" 2>/dev/null || true
    fi
    
    # B2 (manter 7 dias)
    if [ "$B2_ENABLED" = "true" ]; then
        rclone delete "b2:${B2_BUCKET}/" \
            --min-age 7d \
            --include "n8n_backup_*.tar.gz" 2>/dev/null || true
    fi
    
    log_success "Limpeza concluída"
}

# Main
main() {
    log_info "🚀 Iniciando backup - ${TIMESTAMP}"
    send_discord "🚀 **Backup Iniciado**\n\nTimestamp: ${TIMESTAMP}" "info"
    
    # Criar diretório temporário
    mkdir -p "${BACKUP_DIR}"
    
    # Executar backups
    if ! backup_postgresql; then
        send_discord "❌ **Backup PostgreSQL falhou**" "error"
        exit 1
    fi
    
    backup_redis
    
    # Criar arquivo compactado
    log_info "📦 Compactando backup..."
    tar -czf "$BACKUP_ARCHIVE" -C "${BACKUP_LOCAL_DIR}" "$(basename $BACKUP_DIR)"
    rm -rf "${BACKUP_DIR}"
    
    local file_size=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
    log_success "Arquivo criado: $(basename $BACKUP_ARCHIVE) ($file_size)"
    
    # Upload para storages
    upload_to_oracle
    upload_to_b2
    
    # Limpeza
    cleanup_old_backups
    
    # Notificação final
    send_discord "✅ **Backup Concluído!**\n\nArquivo: $(basename $BACKUP_ARCHIVE)\nTamanho: $file_size" "success"
    
    log_success "✅ Backup concluído com sucesso!"
}

trap 'log_error "Backup falhou"; send_discord "❌ **Backup falhou na linha $LINENO**" "error"; exit 1' ERR

main "$@"