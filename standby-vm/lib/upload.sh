#!/bin/bash
# ============================================
# Funções de upload para cloud storage
# Arquivo: /opt/n8n-standby/lib/upload.sh
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/security.sh"

# Configurações de upload
UPLOAD_RETRIES="${UPLOAD_RETRIES:-3}"
UPLOAD_TIMEOUT="${UPLOAD_TIMEOUT:-300}"

# Upload para Oracle
upload_to_oracle() {
    local local_file="$1"
    local remote_path="$2"

    if [ "$ORACLE_ENABLED" != true ]; then
        log_info "Oracle desabilitado, pulando..."
        return 0
    fi

    log_info "Enviando para Oracle: $local_file -> $remote_path"

    local attempt=1
    while [ $attempt -le $UPLOAD_RETRIES ]; do
        log_info "Tentativa $attempt/$UPLOAD_RETRIES..."

        if rclone copy "$local_file" "oracle:$ORACLE_BUCKET/$remote_path" --timeout "${UPLOAD_TIMEOUT}s" --progress --quiet; then
            log_success "Upload Oracle OK: $remote_path"
            return 0
        else
            log_warning "Tentativa $attempt falhou"
            attempt=$((attempt + 1))
            sleep 5
        fi
    done

    log_error "Falha no upload Oracle após $UPLOAD_RETRIES tentativas"
    return 1
}

# Upload para B2
upload_to_b2() {
    local local_file="$1"
    local remote_path="$2"

    if [ "$B2_ENABLED" != true ]; then
        log_info "B2 desabilitado, pulando..."
        return 0
    fi

    log_info "Enviando para B2: $local_file -> $remote_path"

    local attempt=1
    while [ $attempt -le $UPLOAD_RETRIES ]; do
        log_info "Tentativa $attempt/$UPLOAD_RETRIES..."

        if rclone copy "$local_file" "b2:$B2_BUCKET/$remote_path" --timeout "${UPLOAD_TIMEOUT}s" --progress --quiet; then
            log_success "Upload B2 OK: $remote_path"
            return 0
        else
            log_warning "Tentativa $attempt falhou"
            attempt=$((attempt + 1))
            sleep 5
        fi
    done

    log_error "Falha no upload B2 após $UPLOAD_RETRIES tentativas"
    return 1
}

# Upload para múltiplos destinos
upload_file() {
    local local_file="$1"
    local remote_path="$2"

    if [ ! -f "$local_file" ]; then
        log_error "Arquivo para upload não encontrado: $local_file"
        return 1
    fi

    log_info "Iniciando upload: $(basename "$local_file")"

    local success_count=0
    local total_count=0

    # Contar destinos habilitados
    if [ "$ORACLE_ENABLED" = true ]; then
        total_count=$((total_count + 1))
    fi
    if [ "$B2_ENABLED" = true ]; then
        total_count=$((total_count + 1))
    fi

    if [ $total_count -eq 0 ]; then
        log_warning "Nenhum destino de upload habilitado"
        return 1
    fi

    # Upload para Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        if upload_to_oracle "$local_file" "$remote_path"; then
            success_count=$((success_count + 1))
        fi
    fi

    # Upload para B2
    if [ "$B2_ENABLED" = true ]; then
        if upload_to_b2 "$local_file" "$remote_path"; then
            success_count=$((success_count + 1))
        fi
    fi

    # Verificar resultado
    if [ $success_count -eq $total_count ]; then
        log_success "Upload concluído: $success_count/$total_count destinos"
        return 0
    else
        log_error "Upload falhou: $success_count/$total_count destinos"
        return 1
    fi
}

# Download do Oracle
download_from_oracle() {
    local remote_path="$1"
    local local_file="$2"

    if [ "$ORACLE_ENABLED" != true ]; then
        log_info "Oracle desabilitado, pulando..."
        return 1
    fi

    log_info "Baixando do Oracle: $remote_path -> $local_file"

    if rclone copy "oracle:$ORACLE_BUCKET/$remote_path" "$(dirname "$local_file")" --timeout "${UPLOAD_TIMEOUT}s" --progress --quiet; then
        log_success "Download Oracle OK: $local_file"
        return 0
    else
        log_error "Falha no download Oracle"
        return 1
    fi
}

# Download do B2
download_from_b2() {
    local remote_path="$1"
    local local_file="$2"

    if [ "$B2_ENABLED" != true ]; then
        log_info "B2 desabilitado, pulando..."
        return 1
    fi

    log_info "Baixando do B2: $remote_path -> $local_file"

    if rclone copy "b2:$B2_BUCKET/$remote_path" "$(dirname "$local_file")" --timeout "${UPLOAD_TIMEOUT}s" --progress --quiet; then
        log_success "Download B2 OK: $local_file"
        return 0
    else
        log_error "Falha no download B2"
        return 1
    fi
}

# Download com fallback
download_file() {
    local remote_path="$1"
    local local_file="$2"

    log_info "Iniciando download: $remote_path"

    # Tentar Oracle primeiro
    if [ "$ORACLE_ENABLED" = true ]; then
        if download_from_oracle "$remote_path" "$local_file"; then
            return 0
        fi
    fi

    # Fallback para B2
    if [ "$B2_ENABLED" = true ]; then
        if download_from_b2 "$remote_path" "$local_file"; then
            return 0
        fi
    fi

    log_error "Falha no download de todos os destinos"
    return 1
}

# Listar arquivos no Oracle
list_oracle_files() {
    local remote_path="${1:-}"

    if [ "$ORACLE_ENABLED" != true ]; then
        return 1
    fi

    rclone lsf "oracle:$ORACLE_BUCKET/$remote_path"
}

# Listar arquivos no B2
list_b2_files() {
    local remote_path="${1:-}"

    if [ "$B2_ENABLED" != true ]; then
        return 1
    fi

    rclone lsf "b2:$B2_BUCKET/$remote_path"
}

# Verificar se arquivo existe no Oracle
oracle_file_exists() {
    local remote_path="$1"

    if [ "$ORACLE_ENABLED" != true ]; then
        return 1
    fi

    rclone lsf "oracle:$ORACLE_BUCKET/$remote_path" | grep -q "$(basename "$remote_path")"
}

# Verificar se arquivo existe no B2
b2_file_exists() {
    local remote_path="$1"

    if [ "$B2_ENABLED" != true ]; then
        return 1
    fi

    rclone lsf "b2:$B2_BUCKET/$remote_path" | grep -q "$(basename "$remote_path")"
}

# Obter arquivo mais recente
get_latest_backup() {
    local pattern="${1:-postgres.sql.gz.enc}"

    log_info "Procurando backup mais recente: $pattern"

    local latest_file=""
    local latest_date=""

    # Verificar Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        local oracle_files=$(list_oracle_files | grep "$pattern" | sort -r)
        if [ -n "$oracle_files" ]; then
            local oracle_latest=$(echo "$oracle_files" | head -1)
            if [ -n "$oracle_latest" ]; then
                latest_file="$oracle_latest"
                latest_date=$(echo "$oracle_latest" | grep -o '[0-9]\{8\}_[0-9]\{6\}' | head -1)
                log_info "Encontrado no Oracle: $latest_file"
            fi
        fi
    fi

    # Verificar B2
    if [ "$B2_ENABLED" = true ]; then
        local b2_files=$(list_b2_files | grep "$pattern" | sort -r)
        if [ -n "$b2_files" ]; then
            local b2_latest=$(echo "$b2_files" | head -1)
            if [ -n "$b2_latest" ]; then
                local b2_date=$(echo "$b2_latest" | grep -o '[0-9]\{8\}_[0-9]\{6\}' | head -1)
                if [ -z "$latest_date" ] || [ "$b2_date" \> "$latest_date" ]; then
                    latest_file="$b2_latest"
                    latest_date="$b2_date"
                    log_info "Encontrado no B2: $latest_file"
                fi
            fi
        fi
    fi

    if [ -n "$latest_file" ]; then
        echo "$latest_file"
        return 0
    else
        log_warning "Nenhum backup encontrado"
        return 1
    fi
}

# Limpar arquivos antigos na nuvem
cleanup_cloud_backups() {
    local days="${1:-30}"
    local pattern="${2:-*.enc}"

    log_info "Limpando backups antigos ($days dias)..."

    # Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        log_info "Limpando Oracle..."
        rclone delete "oracle:$ORACLE_BUCKET" --min-age "${days}d" --include "$pattern" --quiet
    fi

    # B2
    if [ "$B2_ENABLED" = true ]; then
        log_info "Limpando B2..."
        rclone delete "b2:$B2_BUCKET" --min-age "${days}d" --include "$pattern" --quiet
    fi

    log_success "Limpeza concluída"
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        upload)
            upload_file "$2" "$3"
            ;;
        download)
            download_file "$2" "$3"
            ;;
        list-oracle)
            list_oracle_files "$2"
            ;;
        list-b2)
            list_b2_files "$2"
            ;;
        latest)
            get_latest_backup "$2"
            ;;
        cleanup)
            cleanup_cloud_backups "$2" "$3"
            ;;
        *)
            echo "Uso: $0 {upload|download|list-oracle|list-b2|latest|cleanup} [args...]"
            exit 1
            ;;
    esac
fi
