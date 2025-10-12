#!/bin/bash
# ============================================
# N8N Backup & Restore System - Script Principal
# Arquivo: /opt/n8n-backup/n8n-backup.sh
# ============================================

set -euo pipefail

# Diretório base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações e bibliotecas
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/recovery.sh"
source "${SCRIPT_DIR}/lib/monitoring.sh"

# Modo de operação
MODE=""

# Função principal
main() {
    # Detectar modo automaticamente se não especificado
    if [ $# -eq 0 ]; then
        detect_operation_mode
    else
        MODE="$1"
    fi

    case $MODE in
        backup|BACKUP)
            run_backup
            ;;
        restore|RESTORE)
            run_restore
            ;;
        setup|SETUP)
            run_setup
            ;;
        status|STATUS)
            show_status
            ;;
        recovery|RECOVERY)
            run_disaster_recovery
            ;;
        *)
            show_usage
            ;;
    esac
}

# Detectar modo de operação automaticamente
detect_operation_mode() {
    log_info "Detectando modo de operação..."

    # Verificar se estamos em uma nova VM (modo recovery)
    if is_new_environment; then
        log_info "Nova VM detectada - Modo: RECOVERY"
        MODE="recovery"
        return
    fi

    # Verificar se containers N8N estão rodando (modo backup)
    if docker ps --filter "name=n8n" --format "{{.Names}}" | grep -q n8n; then
        log_info "Ambiente N8N ativo detectado - Modo: BACKUP"
        MODE="backup"
    else
        log_info "Nenhum ambiente ativo - Modo: SETUP"
        MODE="setup"
    fi
}

# Executar backup
run_backup() {
    show_banner
    log_info "=== MODO BACKUP ==="

    # Verificar se é ambiente de produção
    if ! is_production_environment; then
        log_warning "Este não parece ser um ambiente de produção válido"
        if ! confirm "Continuar mesmo assim?" "n"; then
            exit 0
        fi
    fi

    # Executar backup
    "${SCRIPT_DIR}/backup.sh"
}

# Executar restauração
run_restore() {
    show_banner
    log_info "=== MODO RESTORE ==="

    # Executar restore interativo
    "${SCRIPT_DIR}/restore.sh"
}

# Executar setup
run_setup() {
    show_banner
    log_info "=== MODO SETUP ==="

    # Executar instalador
    "${SCRIPT_DIR}/install.sh"
}

# Mostrar status
show_status() {
    show_banner
    log_info "=== STATUS DO SISTEMA ==="

    # Status dos backups
    backup_status_report

    # Status dos containers
    echo ""
    echo "🐳 Containers N8N:"
    if docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}" | grep -q n8n; then
        docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}"
    else
        echo "Nenhum container N8N encontrado"
    fi

    # Status dos storages
    echo ""
    echo "☁️  Storages:"
    check_storage_status
}

# Executar recuperação de desastre
run_disaster_recovery() {
    show_banner
    log_info "=== MODO DISASTER RECOVERY ==="
    log_warning "Este modo irá RECRIAR TODO o ambiente N8N"

    if ! confirm "Tem CERTEZA que quer continuar? Isso pode sobrescrever dados existentes." "n"; then
        exit 0
    fi

    # Executar recuperação completa
    disaster_recovery
}

# Verificar se é ambiente de produção
is_production_environment() {
    # Verificar se containers N8N estão rodando
    docker ps --filter "name=n8n" --format "{{.Names}}" | grep -q n8n && \
    # Verificar se PostgreSQL está acessível
    test_postgres_connection > /dev/null 2>&1
}

# Verificar se é nova VM (sem containers N8N)
is_new_environment() {
    ! docker ps -a --filter "name=n8n" --format "{{.Names}}" | grep -q n8n
}

# Verificar status dos storages
check_storage_status() {
    # Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone lsd "oracle:" > /dev/null 2>&1; then
            echo "  ✓ Oracle Object Storage"
        else
            echo "  ✗ Oracle Object Storage (configurar rclone)"
        fi
    fi

    # B2
    if [ "$B2_ENABLED" = true ]; then
        if rclone lsd "b2:" > /dev/null 2>&1; then
            echo "  ✓ Backblaze B2"
        else
            echo "  ✗ Backblaze B2 (configurar rclone)"
        fi
    fi
}

# Mostrar uso
show_usage() {
    echo "Uso: $0 [modo]"
    echo ""
    echo "Modos disponíveis:"
    echo "  backup    - Executar backup (padrão se ambiente ativo)"
    echo "  restore   - Restauração interativa"
    echo "  setup     - Configuração inicial"
    echo "  status    - Status do sistema"
    echo "  recovery  - Recuperação de desastre (nova VM)"
    echo ""
    echo "Se nenhum modo for especificado, o sistema detecta automaticamente."
    echo ""
    echo "Exemplos:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 status"
}

# Tratamento de sinais
trap 'log_error "Operação interrompida pelo usuário"; exit 1' INT TERM

# Executar
main "$@"
