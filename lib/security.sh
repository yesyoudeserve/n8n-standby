#!/bin/bash
# ============================================
# Funções de Segurança e Criptografia
# Arquivo: /opt/n8n-backup/lib/security.sh
# ============================================

ENCRYPTED_CONFIG_FILE="${SCRIPT_DIR}/config.enc"

# Inicializar segurança (auto-sync rclone)
init_security() {
    log_info "🔐 Inicializando segurança..."
    
    # Sync rclone config para root se necessário
    if [ "$EUID" -eq 0 ]; then
        sync_rclone_to_root
    fi
    
    log_success "Segurança inicializada"
}

# Sincronizar rclone.conf do usuário para root
sync_rclone_to_root() {
    local user_rclone=""
    local root_rclone="/root/.config/rclone/rclone.conf"
    
    # Detectar usuário original
    if [ -n "$SUDO_USER" ]; then
        user_rclone="/home/${SUDO_USER}/.config/rclone/rclone.conf"
    else
        user_rclone="${HOME}/.config/rclone/rclone.conf"
    fi
    
    if [ -f "$user_rclone" ]; then
        log_info "Sincronizando rclone config para root..."
        mkdir -p "$(dirname $root_rclone)"
        cp "$user_rclone" "$root_rclone"
        chmod 600 "$root_rclone"
        log_success "Rclone config sincronizado"
    else
        log_warning "Rclone config não encontrado em: $user_rclone"
    fi
}

# Salvar encryption key no cloud (criptografada)
save_encryption_key_to_cloud() {
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        log_warning "N8N_ENCRYPTION_KEY não definida"
        return 1
    fi
    
    log_info "💾 Salvando encryption key (criptografada)..."
    
    local temp_key_file=$(mktemp)
    echo "$N8N_ENCRYPTION_KEY" > "$temp_key_file"
    
    # Criptografar com senha mestra
    local encrypted_key=$(openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$temp_key_file" 2>/dev/null | base64 -w 0)
    
    rm -f "$temp_key_file"
    
    if [ -z "$encrypted_key" ]; then
        log_error "Falha ao criptografar encryption key"
        return 1
    fi
    
    # Salvar em arquivo
    echo "$encrypted_key" > "${BACKUP_DIR}/n8n_encryption_key.enc"
    
    log_success "Encryption key salva"
    return 0
}

# Criptografar dados sensíveis
encrypt_sensitive_data() {
    local backup_dir=$1
    
    log_info "🔒 Criptografando dados sensíveis..."
    
    # Criptografar config.env se existir
    if [ -f "${backup_dir}/config.env" ]; then
        openssl enc -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$BACKUP_MASTER_PASSWORD" \
            -in "${backup_dir}/config.env" \
            -out "${backup_dir}/config.env.enc" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            rm -f "${backup_dir}/config.env"
            log_success "config.env criptografado"
        fi
    fi
    
    # Criptografar credenciais EasyPanel se existirem
    if [ -d "${backup_dir}/easypanel_configs" ]; then
        find "${backup_dir}/easypanel_configs" -name "*.json" -type f | while read file; do
            openssl enc -aes-256-cbc -salt -pbkdf2 \
                -pass pass:"$BACKUP_MASTER_PASSWORD" \
                -in "$file" \
                -out "${file}.enc" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                rm -f "$file"
            fi
        done
        
        log_success "Configurações EasyPanel criptografadas"
    fi
}

# Descriptografar dados sensíveis
decrypt_sensitive_data() {
    local backup_dir=$1
    
    log_info "🔓 Descriptografando dados sensíveis..."
    
    # Descriptografar config.env.enc
    if [ -f "${backup_dir}/config.env.enc" ]; then
        openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$BACKUP_MASTER_PASSWORD" \
            -in "${backup_dir}/config.env.enc" \
            -out "${backup_dir}/config.env" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_success "config.env descriptografado"
        else
            log_error "Falha ao descriptografar config.env (senha incorreta?)"
            return 1
        fi
    fi
    
    # Descriptografar arquivos .enc
    find "$backup_dir" -name "*.enc" -type f | while read file; do
        local output_file="${file%.enc}"
        
        openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$BACKUP_MASTER_PASSWORD" \
            -in "$file" \
            -out "$output_file" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            rm -f "$file"
        fi
    done
    
    log_success "Descriptografia concluída"
    return 0
}

# Calcular hash de arquivo
calculate_file_hash() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    sha256sum "$file" | awk '{print $1}'
}

# Verificar integridade de arquivo
verify_file_integrity() {
    local file=$1
    local hash_file="${file}.sha256"
    
    if [ ! -f "$hash_file" ]; then
        log_warning "Arquivo de hash não encontrado: $hash_file"
        return 1
    fi
    
    local stored_hash=$(cat "$hash_file")
    local calculated_hash=$(calculate_file_hash "$file")
    
    if [ "$stored_hash" = "$calculated_hash" ]; then
        log_success "Integridade verificada: OK"
        return 0
    else
        log_error "Integridade verificada: FALHOU"
        log_error "Hash esperado: $stored_hash"
        log_error "Hash calculado: $calculated_hash"
        return 1
    fi
}

# Backup do config.env
backup_config_file() {
    log_info "📝 Backup do config.env..."
    
    if [ -f "${SCRIPT_DIR}/config.env" ]; then
        cp "${SCRIPT_DIR}/config.env" "${BACKUP_DIR}/config.env"
        log_success "config.env incluído no backup"
    else
        log_warning "config.env não encontrado"
    fi
}

# Backup da encryption key
backup_encryption_key() {
    save_encryption_key_to_cloud
}