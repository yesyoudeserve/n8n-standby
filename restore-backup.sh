#!/bin/bash
# ============================================
# Script de Restauração VM de Backup
# Versão simplificada e funcional
# ============================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"

# Variáveis
RESTORE_DIR="${BACKUP_LOCAL_DIR}/restore"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Enviar Discord
send_discord() {
    [ -z "$NOTIFY_WEBHOOK" ] && return 0
    local message=$1
    local color="3447003"
    [ "$2" = "error" ] && color="15158332"
    [ "$2" = "success" ] && color="3066993"
    
    curl -s -H "Content-Type: application/json" -d "{\"embeds\":[{\"description\":\"$message\",\"color\":$color}]}" "$NOTIFY_WEBHOOK" > /dev/null 2>&1 || true
}

# Listar backups
list_backups() {
    echo ""
    echo "=== ORACLE BACKUPS ==="
    rclone lsl "oracle:${ORACLE_BUCKET}/" --include "n8n_backup_*.tar.gz" 2>/dev/null | tail -5 || echo "Vazio"
    
    echo ""
    echo "=== B2 BACKUPS ==="
    rclone lsl "b2:${B2_BUCKET}/" --include "n8n_backup_*.tar.gz" 2>/dev/null | tail -5 || echo "Vazio"
    echo ""
}

# Pegar último backup
get_latest() {
    local storage=$1
    local bucket=$2
    rclone lsl "${storage}:${bucket}/" --include "n8n_backup_*.tar.gz" 2>/dev/null | tail -1 | awk '{print $NF}'
}

# Main
main() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Execute como root: sudo $0${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   RESTAURAR BACKUP - VM DE BACKUP      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    list_backups
    
    echo "Escolha:"
    echo "1) Oracle (último)"
    echo "2) B2 (último)"
    echo "0) Cancelar"
    read -p "> " choice
    
    local storage bucket filename
    case $choice in
        1) storage="oracle"; bucket="$ORACLE_BUCKET" ;;
        2) storage="b2"; bucket="$B2_BUCKET" ;;
        0) exit 0 ;;
        *) echo "Inválido"; exit 1 ;;
    esac
    
    filename=$(get_latest "$storage" "$bucket")
    
    if [ -z "$filename" ]; then
        log_error "Nenhum backup encontrado"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}Backup: $filename${NC}"
    echo -e "${YELLOW}Storage: $storage${NC}"
    echo ""
    echo -e "${RED}⚠️  Isso vai SUBSTITUIR todos os dados!${NC}"
    read -p "Digite 'RESTAURAR' para confirmar: " confirm
    
    if [ "$confirm" != "RESTAURAR" ]; then
        echo "Cancelado"
        exit 0
    fi
    
    send_discord "🚀 Restauração iniciada: $filename" "info"
    
    # Limpar e criar diretório
    rm -rf "$RESTORE_DIR"
    mkdir -p "$RESTORE_DIR"
    
    # Download
    log_info "📥 Baixando $filename..."
    if ! rclone copy "${storage}:${bucket}/${filename}" "$RESTORE_DIR/" --progress; then
        log_error "Falha no download"
        send_discord "❌ Download falhou" "error"
        exit 1
    fi
    
    local backup_file="${RESTORE_DIR}/${filename}"
    
    if [ ! -f "$backup_file" ]; then
        log_error "Arquivo não encontrado após download"
        exit 1
    fi
    
    log_success "Download OK ($(du -h $backup_file | cut -f1))"
    
    # Extrair
    log_info "📦 Extraindo..."
    tar -xzf "$backup_file" -C "$RESTORE_DIR"
    
    local backup_folder=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "n8n_backup_*" | head -1)
    
    if [ ! -d "$backup_folder" ]; then
        log_error "Falha na extração"
        exit 1
    fi
    
    log_success "Extraído"
    
    # Detectar containers
    local POSTGRES_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i "postgres" | grep -v "pgadmin\|pgweb" | head -1)
    local REDIS_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i redis | head -1)
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "PostgreSQL container não encontrado"
        exit 1
    fi
    
    log_info "PostgreSQL: $POSTGRES_CONTAINER"
    [ -n "$REDIS_CONTAINER" ] && log_info "Redis: $REDIS_CONTAINER"
    
    # Parar N8N
    log_info "Parando N8N..."
    docker ps --format "{{.Names}}" | grep -i n8n | grep -v postgres | grep -v redis | while read c; do
        docker stop "$c" 2>/dev/null || true
    done
    
    # Restaurar PostgreSQL
    log_info "🗄️  Restaurando PostgreSQL..."
    
    local dump_file="${backup_folder}/postgresql_dump.sql.gz"
    
    if [ ! -f "$dump_file" ]; then
        log_error "Dump não encontrado: $dump_file"
        exit 1
    fi
    
    # Limpar bancos
    docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname NOT IN ('postgres','template0','template1');" 2>/dev/null || true
    docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "DROP DATABASE IF EXISTS n8n;" 2>/dev/null || true
    
    # Restaurar
    gunzip -c "$dump_file" | docker exec -i "$POSTGRES_CONTAINER" psql -U postgres
    
    if [ $? -eq 0 ]; then
        log_success "PostgreSQL restaurado"
    else
        log_error "Falha ao restaurar PostgreSQL"
        send_discord "❌ Falha PostgreSQL" "error"
        exit 1
    fi
    
    # Restaurar Redis (se existir)
    if [ -n "$REDIS_CONTAINER" ]; then
        local redis_file="${backup_folder}/redis_dump.rdb"
        
        if [ -f "$redis_file" ]; then
            log_info "📦 Restaurando Redis..."
            docker stop "$REDIS_CONTAINER" 2>/dev/null || true
            docker cp "$redis_file" "$REDIS_CONTAINER:/data/dump.rdb"
            docker start "$REDIS_CONTAINER"
            log_success "Redis restaurado"
        fi
    fi
    
    # Reiniciar N8N
    log_info "Reiniciando N8N..."
    docker ps -a --format "{{.Names}}" | grep -i n8n | grep -v postgres | grep -v redis | while read c; do
        docker start "$c" 2>/dev/null || true
    done
    
    sleep 5
    
    # Limpar
    rm -rf "$RESTORE_DIR"
    
    log_success "✅ Restauração concluída!"
    send_discord "✅ Restauração concluída: $filename" "success"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     RESTAURAÇÃO CONCLUÍDA! 🎉          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep n8n
    echo ""
}

main "$@"