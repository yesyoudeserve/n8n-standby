#!/bin/bash
# ============================================
# Funções de Segurança e Criptografia
# Arquivo: /opt/n8n-backup/lib/security.sh
# ============================================

# Carregar funções do logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# Chave de criptografia (mesma para backup/restore)
# Armazenada no cloud storage para acesso multi-VM
ENCRYPTION_KEY_FILE="${SCRIPT_DIR}/encryption.key"
CLOUD_ENCRYPTION_KEY="encryption.key.enc"

# Configurar rclone para root (resolver problema mencionado)
setup_rclone_for_root() {
    log_info "Configurando rclone para root..."

    # Criar diretório se não existir
    sudo mkdir -p /root/.config/rclone

    # Copiar configuração do usuário atual
    if [ -f ~/.config/rclone/rclone.conf ]; then
        sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/
        sudo chown root:root /root/.config/rclone/rclone.conf
        sudo chmod 600 /root/.config/rclone/rclone.conf
        log_success "Configuração rclone copiada para root"
    else
        log_error "Arquivo ~/.config/rclone/rclone.conf não encontrado"
        log_info "Execute 'rclone config' primeiro como usuário normal"
        return 1
    fi

    # Testar configuração
    if sudo rclone lsd oracle: > /dev/null 2>&1; then
        log_success "Oracle rclone OK"
    else
        log_warning "Oracle rclone falhou - verificar credenciais"
    fi

    if sudo rclone lsd b2: > /dev/null 2>&1; then
        log_success "B2 rclone OK"
    else
        log_warning "B2 rclone falhou - verificar credenciais"
    fi
}

# Gerar chave de criptografia se não existir
generate_encryption_key() {
    if [ ! -f "$ENCRYPTION_KEY_FILE" ]; then
        log_info "Gerando nova chave de criptografia..."
        openssl rand -hex 32 > "$ENCRYPTION_KEY_FILE"
        chmod 600 "$ENCRYPTION_KEY_FILE"
        log_success "Chave gerada: ${ENCRYPTION_KEY_FILE}"
    fi
}

# Carregar chave de criptografia (local ou cloud)
load_encryption_key() {
    # Tentar carregar do arquivo local
    if [ -f "$ENCRYPTION_KEY_FILE" ]; then
        ENCRYPTION_KEY=$(cat "$ENCRYPTION_KEY_FILE")
        return 0
    fi

    # Tentar baixar do cloud storage
    log_info "Tentando baixar chave do cloud storage..."

    # Tentar Oracle primeiro
    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone ls "oracle:${ORACLE_BUCKET}/${CLOUD_ENCRYPTION_KEY}" > /dev/null 2>&1; then
            log_info "Baixando chave do Oracle..."
            rclone copy "oracle:${ORACLE_BUCKET}/${CLOUD_ENCRYPTION_KEY}" "${SCRIPT_DIR}/" --quiet
            if [ -f "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}" ]; then
                decrypt_file "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}" "$ENCRYPTION_KEY_FILE"
                rm "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}"
                ENCRYPTION_KEY=$(cat "$ENCRYPTION_KEY_FILE")
                log_success "Chave carregada do Oracle"
                return 0
            fi
        fi
    fi

    # Tentar B2
    if [ "$B2_ENABLED" = true ]; then
        if rclone ls "b2:${B2_BUCKET}/${CLOUD_ENCRYPTION_KEY}" > /dev/null 2>&1; then
            log_info "Baixando chave do B2..."
            rclone copy "b2:${B2_BUCKET}/${CLOUD_ENCRYPTION_KEY}" "${SCRIPT_DIR}/" --quiet
            if [ -f "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}" ]; then
                decrypt_file "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}" "$ENCRYPTION_KEY_FILE"
                rm "${SCRIPT_DIR}/${CLOUD_ENCRYPTION_KEY}"
                ENCRYPTION_KEY=$(cat "$ENCRYPTION_KEY_FILE")
                log_success "Chave carregada do B2"
                return 0
            fi
        fi
    fi

    # Se não encontrou, gerar nova
    log_warning "Chave de criptografia não encontrada. Gerando nova..."
    generate_encryption_key
    ENCRYPTION_KEY=$(cat "$ENCRYPTION_KEY_FILE")
}

# Salvar chave de criptografia no cloud
save_encryption_key_to_cloud() {
    log_info "Salvando chave de criptografia no cloud..."

    # Criptografar a chave com uma senha derivada
    local temp_encrypted="${SCRIPT_DIR}/temp_key.enc"
    echo "$ENCRYPTION_KEY" | openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -out "$temp_encrypted"

    # Upload para storages
    local uploaded=false

    if [ "$ORACLE_ENABLED" = true ]; then
        rclone copy "$temp_encrypted" "oracle:${ORACLE_BUCKET}/${CLOUD_ENCRYPTION_KEY}" --quiet
        if [ $? -eq 0 ]; then
            log_success "Chave salva no Oracle"
            uploaded=true
        fi
    fi

    if [ "$B2_ENABLED" = true ]; then
        rclone copy "$temp_encrypted" "b2:${B2_BUCKET}/${CLOUD_ENCRYPTION_KEY}" --quiet
        if [ $? -eq 0 ]; then
            log_success "Chave salva no B2"
            uploaded=true
        fi
    fi

    rm "$temp_encrypted"

    if [ "$uploaded" = true ]; then
        log_success "Chave de criptografia armazenada com segurança no cloud"
    else
        log_error "Falha ao salvar chave no cloud"
    fi
}

# Criptografar arquivo
encrypt_file() {
    local input_file=$1
    local output_file=$2

    if [ ! -f "$input_file" ]; then
        log_error "Arquivo para criptografar não encontrado: $input_file"
        return 1
    fi

    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$ENCRYPTION_KEY" \
        -in "$input_file" \
        -out "$output_file"

    if [ $? -eq 0 ]; then
        log_success "Arquivo criptografado: $output_file"
        return 0
    else
        log_error "Falha na criptografia"
        return 1
    fi
}

# Descriptografar arquivo
decrypt_file() {
    local input_file=$1
    local output_file=$2

    if [ ! -f "$input_file" ]; then
        log_error "Arquivo para descriptografar não encontrado: $input_file"
        return 1
    fi

    openssl enc -d -aes-256-cbc -pbkdf2 \
        -pass pass:"$ENCRYPTION_KEY" \
        -in "$input_file" \
        -out "$output_file"

    if [ $? -eq 0 ]; then
        log_success "Arquivo descriptografado: $output_file"
        return 0
    else
        log_error "Falha na descriptografia"
        return 1
    fi
}

# Calcular hash SHA256 de arquivo
calculate_file_hash() {
    local file=$1
    sha256sum "$file" | awk '{print $1}'
}

# Verificar integridade de arquivo
verify_file_integrity() {
    local file=$1
    local expected_hash=$2

    local actual_hash=$(calculate_file_hash "$file")

    if [ "$actual_hash" = "$expected_hash" ]; then
        log_success "Integridade verificada: $file"
        return 0
    else
        log_error "Integridade comprometida!"
        log_error "Esperado: $expected_hash"
        log_error "Atual:    $actual_hash"
        return 1
    fi
}

# Criptografar credenciais sensíveis no backup
encrypt_sensitive_data() {
    local backup_dir=$1

    log_info "Criptografando dados sensíveis..."

    # Arquivos a criptografar
    local sensitive_files=(
        "encryption_key.txt"
        "postgres_password.txt"
        "easypanel_configs/*_env.json"
        "config.env"  # NOVO: Configurações também!
    )

    for pattern in "${sensitive_files[@]}"; do
        for file in $(find "$backup_dir" -name "$pattern" 2>/dev/null); do
            if [ -f "$file" ]; then
                local encrypted_file="${file}.enc"
                if encrypt_file "$file" "$encrypted_file"; then
                    rm "$file"  # Remover arquivo original
                    log_info "Criptografado: $(basename "$file")"
                fi
            fi
        done
    done
}

# Descriptografar credenciais no restore
decrypt_sensitive_data() {
    local backup_dir=$1

    log_info "Descriptografando dados sensíveis..."

    # Arquivos a descriptografar
    find "$backup_dir" -name "*.enc" | while read encrypted_file; do
        local original_file="${encrypted_file%.enc}"
        if decrypt_file "$encrypted_file" "$original_file"; then
            rm "$encrypted_file"  # Remover arquivo criptografado
            log_info "Descriptografado: $(basename "$original_file")"
        fi
    done
}

# Backup seguro da encryption key do N8N
backup_n8n_encryption_key_securely() {
    local backup_dir=$1

    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ "$N8N_ENCRYPTION_KEY" = "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ]; then
        log_warning "N8N_ENCRYPTION_KEY não configurada!"
        return 1
    fi

    # Salvar de forma criptografada
    echo "$N8N_ENCRYPTION_KEY" > "${backup_dir}/n8n_key.tmp"
    encrypt_file "${backup_dir}/n8n_key.tmp" "${backup_dir}/encryption_key.txt.enc"
    rm "${backup_dir}/n8n_key.tmp"

    log_success "N8N encryption key salva de forma segura"
}

# Validar senha mestra para operações críticas
validate_master_password() {
    if [ -z "$BACKUP_MASTER_PASSWORD" ]; then
        log_error "BACKUP_MASTER_PASSWORD não configurada!"
        log_info "Configure no config.env para operações de segurança"
        return 1
    fi

    # Verificar força da senha
    if [ ${#BACKUP_MASTER_PASSWORD} -lt 12 ]; then
        log_warning "Senha mestra muito fraca (mínimo 12 caracteres)"
        return 1
    fi

    return 0
}

# Inicializar segurança
init_security() {
    # Resolver problema do rclone com root
    setup_rclone_for_root

    # Carregar chave de criptografia
    load_encryption_key

    # Validar senha mestra
    validate_master_password
}
