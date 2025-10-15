#!/bin/bash
# ============================================
# Funções PostgreSQL para backup/restore
# Arquivo: /opt/n8n-standby/lib/postgres.sh
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/security.sh"

# Configurações PostgreSQL
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

# Arquivos de backup
BACKUP_DIR="${SCRIPT_DIR}/backups"
POSTGRES_BACKUP_FILE="${BACKUP_DIR}/postgres.sql.gz"
POSTGRES_BACKUP_ENCRYPTED="${BACKUP_DIR}/postgres.sql.gz.enc"

# Criar diretório de backups
create_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
}

# Verificar conexão PostgreSQL
check_postgres_connection() {
    log_info "Verificando conexão PostgreSQL..."

    # Verificar se variáveis estão configuradas
    if [ -z "$POSTGRES_PASSWORD" ]; then
        log_error "POSTGRES_PASSWORD não configurada!"
        return 1
    fi

    # Testar conexão
    export PGPASSWORD="$POSTGRES_PASSWORD"

    if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Conexão PostgreSQL OK"
        return 0
    else
        log_error "Falha na conexão PostgreSQL"
        log_error "Host: $POSTGRES_HOST:$POSTGRES_PORT"
        log_error "User: $POSTGRES_USER"
        log_error "DB: $POSTGRES_DB"
        return 1
    fi
}

# Backup do PostgreSQL
backup_postgres() {
    log_info "Iniciando backup PostgreSQL..."

    create_backup_dir

    # Verificar conexão
    if ! check_postgres_connection; then
        return 1
    fi

    # Comando de backup
    local backup_cmd="pg_dump -h '$POSTGRES_HOST' -p '$POSTGRES_PORT' -U '$POSTGRES_USER' -d '$POSTGRES_DB' --no-password --format=custom --compress=9 --verbose"

    log_info "Executando: $backup_cmd"

    # Executar backup
    if eval "$backup_cmd" | pv -pterb > "${POSTGRES_BACKUP_FILE}.tmp"; then
        mv "${POSTGRES_BACKUP_FILE}.tmp" "$POSTGRES_BACKUP_FILE"
        log_success "Backup PostgreSQL criado: $POSTGRES_BACKUP_FILE"

        # Mostrar tamanho
        local size=$(stat -f%z "$POSTGRES_BACKUP_FILE" 2>/dev/null || stat -c%s "$POSTGRES_BACKUP_FILE" 2>/dev/null)
        log_info "Tamanho: $(format_size "$size")"

        return 0
    else
        log_error "Falha no backup PostgreSQL"
        rm -f "${POSTGRES_BACKUP_FILE}.tmp"
        return 1
    fi
}

# Restore do PostgreSQL
restore_postgres() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        backup_file="$POSTGRES_BACKUP_FILE"
    fi

    log_info "Iniciando restore PostgreSQL..."
    log_info "Arquivo: $backup_file"

    # Verificar se arquivo existe
    if [ ! -f "$backup_file" ]; then
        log_error "Arquivo de backup não encontrado: $backup_file"
        return 1
    fi

    # Verificar conexão
    if ! check_postgres_connection; then
        return 1
    fi

    # Confirmar operação destrutiva
    if ! confirm "ATENÇÃO: Isso vai APAGAR todos os dados atuais. Continuar?"; then
        log_info "Restore cancelado pelo usuário"
        return 1
    fi

    # Parar serviços que usam o banco
    log_warning "Parando serviços que usam PostgreSQL..."
    sudo systemctl stop n8n 2>/dev/null || true
    sudo systemctl stop n8n-worker 2>/dev/null || true
    sudo systemctl stop n8n-webhook 2>/dev/null || true

    # Aguardar
    sleep 3

    # Comando de restore
    local restore_cmd="pg_restore -h '$POSTGRES_HOST' -p '$POSTGRES_PORT' -U '$POSTGRES_USER' -d '$POSTGRES_DB' --no-password --clean --create --verbose '$backup_file'"

    log_info "Executando: $restore_cmd"

    # Executar restore
    if eval "$restore_cmd"; then
        log_success "Restore PostgreSQL concluído"

        # Reiniciar serviços
        log_info "Reiniciando serviços..."
        sudo systemctl start n8n 2>/dev/null || true
        sudo systemctl start n8n-worker 2>/dev/null || true
        sudo systemctl start n8n-webhook 2>/dev/null || true

        return 0
    else
        log_error "Falha no restore PostgreSQL"

        # Tentar reiniciar serviços mesmo com erro
        sudo systemctl start n8n 2>/dev/null || true
        sudo systemctl start n8n-worker 2>/dev/null || true
        sudo systemctl start n8n-webhook 2>/dev/null || true

        return 1
    fi
}

# Limpar backups antigos
cleanup_old_backups() {
    local days="${1:-30}"

    log_info "Limpando backups PostgreSQL com mais de ${days} dias..."

    find "$BACKUP_DIR" -name "postgres.sql.gz*" -mtime +"$days" -delete

    log_success "Limpeza concluída"
}

# Verificar integridade do backup
verify_postgres_backup() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        backup_file="$POSTGRES_BACKUP_FILE"
    fi

    log_info "Verificando integridade do backup: $backup_file"

    if [ ! -f "$backup_file" ]; then
        log_error "Arquivo não encontrado: $backup_file"
        return 1
    fi

    # Tentar listar conteúdo do backup
    if pg_restore --list "$backup_file" > /dev/null 2>&1; then
        log_success "Backup PostgreSQL íntegro"
        return 0
    else
        log_error "Backup PostgreSQL corrompido"
        return 1
    fi
}

# Obter informações do banco
get_postgres_info() {
    log_info "Informações do PostgreSQL:"

    export PGPASSWORD="$POSTGRES_PASSWORD"

    echo "Host: $POSTGRES_HOST:$POSTGRES_PORT"
    echo "User: $POSTGRES_USER"
    echo "Database: $POSTGRES_DB"

    # Versão do PostgreSQL
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" 2>/dev/null | head -3 | tail -1

    # Tamanho do banco
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));" 2>/dev/null | head -3 | tail -1

    # Número de tabelas
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | head -3 | tail -1
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        backup)
            backup_postgres
            ;;
        restore)
            restore_postgres "$2"
            ;;
        verify)
            verify_postgres_backup "$2"
            ;;
        info)
            get_postgres_info
            ;;
        cleanup)
            cleanup_old_backups "$2"
            ;;
        *)
            echo "Uso: $0 {backup|restore|verify|info|cleanup} [arquivo]"
            exit 1
            ;;
    esac
fi
