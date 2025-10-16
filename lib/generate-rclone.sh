#!/bin/bash
# ============================================
# Gerador de rclone.conf
# Arquivo: /opt/n8n-backup/lib/generate-rclone.sh
# ============================================

# Gerar configuração rclone
generate_rclone_config() {
    log_info "🔧 Gerando rclone.conf..."
    
    local rclone_dir="${HOME}/.config/rclone"
    local rclone_conf="${rclone_dir}/rclone.conf"
    
    # Criar diretório se não existir
    mkdir -p "$rclone_dir"
    
    # Gerar configuração
    cat > "$rclone_conf" <<EOF
# Rclone Configuration - Auto-generated
# Date: $(date)

[oracle]
type = s3
provider = Other
access_key_id = ${ORACLE_ACCESS_KEY}
secret_access_key = ${ORACLE_SECRET_KEY}
region = ${ORACLE_REGION}
endpoint = ${ORACLE_NAMESPACE}.compat.objectstorage.${ORACLE_REGION}.oraclecloud.com
acl = private
no_check_bucket = true

EOF

    # B2 - verificar se usa chaves separadas
    if [ "$B2_USE_SEPARATE_KEYS" = "true" ]; then
        # B2 para dados
        cat >> "$rclone_conf" <<EOF
[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_DATA_KEY}
hard_delete = false

[b2-config]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_CONFIG_KEY}
hard_delete = false

EOF
    else
        # B2 com chave master única
        cat >> "$rclone_conf" <<EOF
[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
hard_delete = false

EOF
    fi
    
    # Definir permissões seguras
    chmod 600 "$rclone_conf"
    
    log_success "rclone.conf gerado em: $rclone_conf"
    
    # Se for root, criar também em /root
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        local root_rclone_dir="/root/.config/rclone"
        local root_rclone_conf="${root_rclone_dir}/rclone.conf"
        
        mkdir -p "$root_rclone_dir"
        cp "$rclone_conf" "$root_rclone_conf"
        chmod 600 "$root_rclone_conf"
        
        log_info "rclone.conf também copiado para /root"
    fi
    
    # Testar configuração
    test_rclone_config
}

# Testar configuração rclone
test_rclone_config() {
    log_info "🧪 Testando conexões rclone..."
    
    local all_ok=true
    
    # Testar Oracle
    if [ "$ORACLE_ENABLED" = "true" ]; then
        if rclone lsd oracle: > /dev/null 2>&1; then
            log_success "✅ Oracle: OK"
        else
            log_error "❌ Oracle: FALHOU"
            all_ok=false
        fi
    fi
    
    # Testar B2
    if [ "$B2_ENABLED" = "true" ]; then
        if rclone lsd b2: > /dev/null 2>&1; then
            log_success "✅ B2: OK"
        else
            log_error "❌ B2: FALHOU"
            all_ok=false
        fi
        
        # Testar b2-config se usar chaves separadas
        if [ "$B2_USE_SEPARATE_KEYS" = "true" ]; then
            if rclone lsd b2-config: > /dev/null 2>&1; then
                log_success "✅ B2-config: OK"
            else
                log_error "❌ B2-config: FALHOU"
                all_ok=false
            fi
        fi
    fi
    
    if [ "$all_ok" = true ]; then
        log_success "Todos os storages testados com sucesso"
        return 0
    else
        log_warning "Alguns storages falharam no teste"
        return 1
    fi
}

# Exportar configuração (para compartilhar entre VMs)
export_rclone_config() {
    local output_file="${1:-${SCRIPT_DIR}/rclone.conf.backup}"
    local rclone_conf="${HOME}/.config/rclone/rclone.conf"
    
    if [ ! -f "$rclone_conf" ]; then
        log_error "rclone.conf não encontrado"
        return 1
    fi
    
    log_info "📤 Exportando rclone.conf..."
    
    # Criptografar antes de exportar
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$rclone_conf" \
        -out "$output_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "rclone.conf exportado para: $output_file"
        return 0
    else
        log_error "Falha ao exportar rclone.conf"
        return 1
    fi
}

# Importar configuração
import_rclone_config() {
    local input_file="${1:-${SCRIPT_DIR}/rclone.conf.backup}"
    local rclone_dir="${HOME}/.config/rclone"
    local rclone_conf="${rclone_dir}/rclone.conf"
    
    if [ ! -f "$input_file" ]; then
        log_error "Arquivo não encontrado: $input_file"
        return 1
    fi
    
    log_info "📥 Importando rclone.conf..."
    
    mkdir -p "$rclone_dir"
    
    # Descriptografar
    openssl enc -d -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$input_file" \
        -out "$rclone_conf" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        chmod 600 "$rclone_conf"
        log_success "rclone.conf importado com sucesso"
        test_rclone_config
        return 0
    else
        log_error "Falha ao importar rclone.conf (senha incorreta?)"
        return 1
    fi
}