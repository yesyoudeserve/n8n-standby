#!/bin/bash
# ============================================
# lib/setup.sh - Função load_encrypted_config() ROBUSTA
# Com validação e fallback Oracle → B2 → Nova instalação
# ============================================

# Verificar se arquivo existe no storage remoto
check_remote_file_exists() {
    local remote=$1
    local bucket=$2
    local filename=$3
    
    log_info "🔍 Verificando se $filename existe em $remote:$bucket/..."
    
    # Listar arquivo específico
    local result=$(rclone lsf "${remote}:${bucket}/${filename}" 2>/dev/null)
    
    if [ -n "$result" ]; then
        log_success "✅ Arquivo encontrado em $remote"
        return 0
    else
        log_warning "❌ Arquivo NÃO encontrado em $remote"
        return 1
    fi
}

# Baixar e validar arquivo
download_and_validate() {
    local remote=$1
    local bucket=$2
    local filename=$3
    local destination=$4
    
    log_info "📥 Baixando de ${remote}:${bucket}/${filename}..."
    
    # Criar arquivo temporário
    local temp_file="${destination}.tmp"
    
    # Tentar download com timeout
    if timeout 30 rclone copy "${remote}:${bucket}/${filename}" "$(dirname $destination)/" --progress 2>&1 | grep -v "^$"; then
        
        # Renomear de .tmp se necessário (rclone não cria .tmp, mas por segurança)
        if [ -f "${destination}.tmp" ]; then
            mv "${destination}.tmp" "${destination}"
        fi
        
        # Verificar se arquivo foi criado
        if [ ! -f "$destination" ]; then
            log_error "❌ Download executado mas arquivo não foi salvo"
            return 1
        fi
        
        # Verificar tamanho (deve ter pelo menos 100 bytes)
        local file_size=$(stat -c%s "$destination" 2>/dev/null || echo "0")
        
        if [ "$file_size" -lt 100 ]; then
            log_error "❌ Arquivo muito pequeno ($file_size bytes) - provavelmente corrompido"
            rm -f "$destination"
            return 1
        fi
        
        # Verificar se é um arquivo criptografado válido (começa com "Salted__")
        local file_header=$(head -c 8 "$destination" 2>/dev/null | base64 2>/dev/null)
        
        if [[ "$file_header" == *"U2FsdGVk"* ]]; then
            log_success "✅ Arquivo válido baixado ($file_size bytes)"
            return 0
        else
            log_error "❌ Arquivo não parece ser criptografia OpenSSL válida"
            log_error "   Header: $file_header"
            rm -f "$destination"
            return 1
        fi
        
    else
        log_error "❌ Falha no download de $remote"
        rm -f "$destination" "${destination}.tmp"
        return 1
    fi
}

# Tentar descriptografar arquivo
try_decrypt() {
    local encrypted_file=$1
    local password=$2
    local output_file=$3
    
    log_info "🔓 Tentando descriptografar..."
    
    openssl enc -d -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$password" \
        -in "$encrypted_file" \
        -out "$output_file" 2>/dev/null
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -s "$output_file" ]; then
        # Validar que é um arquivo .env válido
        if grep -q "=" "$output_file" 2>/dev/null; then
            log_success "✅ Descriptografia bem-sucedida"
            return 0
        else
            log_error "❌ Arquivo descriptografado mas formato inválido"
            rm -f "$output_file"
            return 1
        fi
    else
        log_error "❌ Falha na descriptografia (senha incorreta ou arquivo corrompido)"
        rm -f "$output_file"
        return 1
    fi
}

# Carregar config do cloud (VERSÃO ROBUSTA COM FALLBACK)
load_encrypted_config() {
    echo ""
    echo -e "${BLUE}🔑 Digite sua senha mestra:${NC}"
    echo -n "> "
    read -s MASTER_PASSWORD
    echo ""

    [ -z "$MASTER_PASSWORD" ] && return 1

    log_info "📥 Buscando configuração nos storages..."
    echo ""

    # Garantir permissões corretas do diretório
    mkdir -p "${SCRIPT_DIR}"
    chmod 755 "${SCRIPT_DIR}"

    # Tentar carregar metadados do Supabase primeiro
    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        log_info "📊 Metadados carregados do Supabase"
        
        # Gerar configuração rclone
        source "${SCRIPT_DIR}/lib/generate-rclone.sh"
        generate_rclone_config
        
        log_success "✅ Rclone configurado"
    else
        log_warning "⚠️  Metadados não encontrados no Supabase"
        log_info "   Tentando buscar configuração diretamente nos storages..."
    fi

    echo ""
    log_info "🔍 Estratégia: Oracle → B2 → Nova Instalação"
    echo ""

    local config_loaded=false
    local download_source=""
    
    # ========================================
    # TENTATIVA 1: ORACLE
    # ========================================
    if [ "$ORACLE_ENABLED" = "true" ] && rclone listremotes 2>/dev/null | grep -q "oracle:"; then
        log_info "📦 [1/2] Tentando Oracle..."
        
        # Verificar se arquivo existe
        if check_remote_file_exists "oracle" "$ORACLE_CONFIG_BUCKET" "config.enc"; then
            
            # Baixar e validar
            if download_and_validate "oracle" "$ORACLE_CONFIG_BUCKET" "config.enc" "$ENCRYPTED_CONFIG_FILE"; then
                
                # Tentar descriptografar
                local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
                if try_decrypt "$ENCRYPTED_CONFIG_FILE" "$MASTER_PASSWORD" "$temp_decrypted"; then
                    
                    # Sucesso! Carregar variáveis
                    source "$temp_decrypted"
                    apply_config_to_env
                    
                    # Limpar temporários
                    rm -f "$temp_decrypted" "$ENCRYPTED_CONFIG_FILE"
                    
                    config_loaded=true
                    download_source="Oracle"
                    
                    echo ""
                    log_success "🎉 Configuração carregada com sucesso do Oracle!"
                    return 0
                else
                    log_warning "⚠️  Oracle: Descriptografia falhou"
                    rm -f "$ENCRYPTED_CONFIG_FILE"
                fi
            else
                log_warning "⚠️  Oracle: Download ou validação falhou"
            fi
        else
            log_warning "⚠️  Oracle: Arquivo config.enc não existe no bucket"
        fi
        
    else
        log_warning "⚠️  Oracle não disponível ou não habilitado"
    fi

    echo ""
    
    # ========================================
    # TENTATIVA 2: B2 (FALLBACK)
    # ========================================
    if [ "$config_loaded" = false ] && [ "$B2_ENABLED" = "true" ]; then
        
        # Determinar remote correto
        local b2_remote="b2"
        if [ "$B2_USE_SEPARATE_KEYS" = "true" ]; then
            b2_remote="b2-config"
        fi
        
        if rclone listremotes 2>/dev/null | grep -q "${b2_remote}:"; then
            log_info "📦 [2/2] Tentando B2 (fallback)..."
            
            # Verificar se arquivo existe
            if check_remote_file_exists "$b2_remote" "$B2_CONFIG_BUCKET" "config.enc"; then
                
                # Baixar e validar
                if download_and_validate "$b2_remote" "$B2_CONFIG_BUCKET" "config.enc" "$ENCRYPTED_CONFIG_FILE"; then
                    
                    # Tentar descriptografar
                    local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
                    if try_decrypt "$ENCRYPTED_CONFIG_FILE" "$MASTER_PASSWORD" "$temp_decrypted"; then
                        
                        # Sucesso! Carregar variáveis
                        source "$temp_decrypted"
                        apply_config_to_env
                        
                        # Limpar temporários
                        rm -f "$temp_decrypted" "$ENCRYPTED_CONFIG_FILE"
                        
                        config_loaded=true
                        download_source="B2"
                        
                        echo ""
                        log_success "🎉 Configuração carregada com sucesso do B2!"
                        
                        # IMPORTANTE: Sincronizar para Oracle
                        log_warning "⚠️  Oracle estava sem o arquivo. Sincronizando do B2 → Oracle..."
                        if upload_encrypted_config; then
                            log_success "✅ Oracle sincronizado com B2"
                        fi
                        
                        return 0
                    else
                        log_warning "⚠️  B2: Descriptografia falhou"
                        rm -f "$ENCRYPTED_CONFIG_FILE"
                    fi
                else
                    log_warning "⚠️  B2: Download ou validação falhou"
                fi
            else
                log_warning "⚠️  B2: Arquivo config.enc não existe no bucket"
            fi
            
        else
            log_warning "⚠️  B2 não disponível ou não configurado"
        fi
    fi

    echo ""
    
    # ========================================
    # TENTATIVA 3: NOVA INSTALAÇÃO
    # ========================================
    if [ "$config_loaded" = false ]; then
        log_warning "❌ Nenhuma configuração encontrada em Oracle ou B2"
        log_info "📝 Iniciando nova instalação..."
        return 1  # Retorna 1 para acionar "primeira instalação"
    fi
}

# Função auxiliar para sincronizar Oracle quando B2 está OK mas Oracle não
sync_oracle_from_b2() {
    log_info "🔄 Sincronizando configuração: B2 → Oracle..."
    
    local b2_remote="b2"
    [ "$B2_USE_SEPARATE_KEYS" = "true" ] && b2_remote="b2-config"
    
    # Copiar diretamente entre storages
    if rclone copy "${b2_remote}:${B2_CONFIG_BUCKET}/config.enc" "oracle:${ORACLE_CONFIG_BUCKET}/" --progress; then
        log_success "✅ Sincronização concluída"
        return 0
    else
        log_error "❌ Falha na sincronização"
        return 1
    fi
}