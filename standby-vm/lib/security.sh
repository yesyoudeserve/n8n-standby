#!/bin/bash
# ============================================
# Funções de Segurança e Criptografia
# Arquivo: /opt/n8n-standby/lib/security.sh
# ============================================

# Carregar funções do logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# Chave de criptografia (mesma para backup/restore)
ENCRYPTION_KEY_FILE="${SCRIPT_DIR}/encryption.key"
CLOUD_ENCRYPTION_KEY="encryption.key.enc"

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
        if rclone lsf "oracle:${ORACLE_BUCKET}/" | grep -q "$CLOUD_ENCRYPTION_KEY"; then
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
        if rclone lsf "b2:${B2_BUCKET}/" | grep -q "$CLOUD_ENCRYPTION_KEY"; then
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

# Inicializar segurança
init_security() {
    # Carregar chave de criptografia
    load_encryption_key

    # Validar senha mestra
    validate_master_password
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
