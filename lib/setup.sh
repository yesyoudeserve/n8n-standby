#!/bin/bash
# ============================================
# Configuração Automática e Interativa
# Arquivo: /opt/n8n-backup/lib/setup.sh
# Versão: 4.0 - Lógica Master Password
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Carregar funções do logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# Arquivo de configuração criptografada
ENCRYPTED_CONFIG_FILE="${SCRIPT_DIR}/config.enc"

# Função para detectar credenciais automaticamente
detect_credentials() {
    log_info "🔍 Detectando credenciais automaticamente..."

    # Detectar N8N Encryption Key
    N8N_CONTAINER=$(sudo docker ps --filter "name=n8n" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
    if [ -n "$N8N_CONTAINER" ]; then
        DETECTED_N8N_KEY=$(sudo docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
        if [ -n "$DETECTED_N8N_KEY" ]; then
            N8N_ENCRYPTION_KEY="$DETECTED_N8N_KEY"
            echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY auto-detectada${NC}"
        fi
    fi

    # Detectar PostgreSQL Password
    POSTGRES_CONTAINER=$(sudo docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "postgres" | head -1 || echo "")
    if [ -n "$POSTGRES_CONTAINER" ]; then
        DETECTED_POSTGRES_PASS=$(sudo docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
        if [ -n "$DETECTED_POSTGRES_PASS" ]; then
            N8N_POSTGRES_PASSWORD="$DETECTED_POSTGRES_PASS"
            echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD auto-detectada${NC}"
        fi
    fi
}

# Função para perguntar TODAS as credenciais (primeira instalação)
ask_all_credentials() {
    echo ""
    echo -e "${BLUE}🔐 Configuração Completa (Primeira Instalação)${NC}"
    echo -e "${BLUE}================================================${NC}"

    # Senha mestra
    while true; do
        echo ""
        echo -e "${YELLOW}Crie uma senha mestra forte (mínimo 12 caracteres):${NC}"
        echo -e "${CYAN}Esta senha protegerá todas as suas credenciais!${NC}"
        echo -n "> "
        read -s BACKUP_MASTER_PASSWORD
        echo ""

        if [ -z "$BACKUP_MASTER_PASSWORD" ]; then
            echo -e "${RED}❌ Senha não pode ser vazia!${NC}"
            continue
        fi

        if [ ${#BACKUP_MASTER_PASSWORD} -lt 12 ]; then
            echo -e "${RED}❌ Senha muito curta! Mínimo 12 caracteres.${NC}"
            continue
        fi

        echo -e "${YELLOW}Confirme a senha mestra:${NC}"
        echo -n "> "
        read -s CONFIRM_PASSWORD
        echo ""

        if [ "$BACKUP_MASTER_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
            echo -e "${RED}❌ As senhas não coincidem!${NC}"
            continue
        fi

        echo -e "${GREEN}✓ Senha mestra criada (${#BACKUP_MASTER_PASSWORD} caracteres)${NC}"
        break
    done

    # N8N Encryption Key
    echo ""
    echo -e "${YELLOW}N8N_ENCRYPTION_KEY:${NC}"
    if [ -n "$N8N_ENCRYPTION_KEY" ]; then
        echo -e "${CYAN}(Auto-detectada - pressione ENTER para usar)${NC}"
    fi
    echo -n "> "
    read INPUT_KEY
    if [ -n "$INPUT_KEY" ]; then
        N8N_ENCRYPTION_KEY="$INPUT_KEY"
    fi
    while [ -z "$N8N_ENCRYPTION_KEY" ]; do
        echo -e "${RED}❌ Encryption key não pode ser vazia!${NC}"
        echo -n "> "
        read N8N_ENCRYPTION_KEY
    done
    echo -e "${GREEN}✓ N8N Encryption Key configurada${NC}"

    # PostgreSQL Password
    echo ""
    echo -e "${YELLOW}N8N_POSTGRES_PASSWORD:${NC}"
    if [ -n "$N8N_POSTGRES_PASSWORD" ]; then
        echo -e "${CYAN}(Auto-detectada - pressione ENTER para usar)${NC}"
    fi
    echo -n "> "
    read INPUT_PASS
    if [ -n "$INPUT_PASS" ]; then
        N8N_POSTGRES_PASSWORD="$INPUT_PASS"
    fi
    while [ -z "$N8N_POSTGRES_PASSWORD" ]; do
        echo -e "${RED}❌ PostgreSQL password não pode ser vazia!${NC}"
        echo -n "> "
        read N8N_POSTGRES_PASSWORD
    done
    echo -e "${GREEN}✓ PostgreSQL Password configurada${NC}"

    # Oracle
    echo ""
    echo -e "${BLUE}Oracle Object Storage (S3-compatible):${NC}"
    
    echo -e "${YELLOW}ORACLE_NAMESPACE:${NC}"
    echo -n "> "
    read ORACLE_NAMESPACE
    while [ -z "$ORACLE_NAMESPACE" ]; do
        echo -e "${RED}❌ Não pode ser vazio!${NC}"
        echo -n "> "
        read ORACLE_NAMESPACE
    done

    echo -e "${YELLOW}ORACLE_REGION (ex: eu-madrid-1):${NC}"
    echo -n "> "
    read ORACLE_REGION
    ORACLE_REGION=${ORACLE_REGION:-eu-madrid-1}

    echo -e "${YELLOW}ORACLE_ACCESS_KEY:${NC}"
    echo -n "> "
    read ORACLE_ACCESS_KEY
    while [ -z "$ORACLE_ACCESS_KEY" ]; do
        echo -e "${RED}❌ Não pode ser vazio!${NC}"
        echo -n "> "
        read ORACLE_ACCESS_KEY
    done

    echo -e "${YELLOW}ORACLE_SECRET_KEY:${NC}"
    echo -n "> "
    read -s ORACLE_SECRET_KEY
    echo ""
    while [ -z "$ORACLE_SECRET_KEY" ]; do
        echo -e "${RED}❌ Não pode ser vazio!${NC}"
        echo -n "> "
        read -s ORACLE_SECRET_KEY
        echo ""
    done

    echo -e "${YELLOW}ORACLE_BUCKET (ex: n8n-backups):${NC}"
    echo -n "> "
    read ORACLE_BUCKET
    ORACLE_BUCKET=${ORACLE_BUCKET:-n8n-backups}

    echo -e "${YELLOW}ORACLE_CONFIG_BUCKET (ex: n8n-config):${NC}"
    echo -n "> "
    read ORACLE_CONFIG_BUCKET
    ORACLE_CONFIG_BUCKET=${ORACLE_CONFIG_BUCKET:-n8n-config}

    echo -e "${GREEN}✓ Oracle configurado${NC}"

    # B2
    echo ""
    echo -e "${BLUE}Backblaze B2:${NC}"
    
    echo -e "${YELLOW}B2_ACCOUNT_ID:${NC}"
    echo -n "> "
    read B2_ACCOUNT_ID
    while [ -z "$B2_ACCOUNT_ID" ]; do
        echo -e "${RED}❌ Não pode ser vazio!${NC}"
        echo -n "> "
        read B2_ACCOUNT_ID
    done

    echo ""
    echo -e "${YELLOW}Chaves B2 específicas por bucket?${NC}"
    echo "1) Não - Master Key"
    echo "2) Sim - Chaves separadas"
    echo -n "> [1]: "
    read B2_KEY_TYPE
    B2_KEY_TYPE=${B2_KEY_TYPE:-1}

    if [ "$B2_KEY_TYPE" = "2" ]; then
        echo -e "${YELLOW}B2_DATA_KEY (para dados):${NC}"
        echo -n "> "
        read -s B2_DATA_KEY
        echo ""
        while [ -z "$B2_DATA_KEY" ]; do
            echo -e "${RED}❌ Não pode ser vazio!${NC}"
            echo -n "> "
            read -s B2_DATA_KEY
            echo ""
        done

        echo -e "${YELLOW}B2_CONFIG_KEY (para config):${NC}"
        echo -n "> "
        read -s B2_CONFIG_KEY
        echo ""
        while [ -z "$B2_CONFIG_KEY" ]; do
            echo -e "${RED}❌ Não pode ser vazio!${NC}"
            echo -n "> "
            read -s B2_CONFIG_KEY
            echo ""
        done
        
        B2_USE_SEPARATE_KEYS=true
        B2_APPLICATION_KEY=""
    else
        echo -e "${YELLOW}B2_APPLICATION_KEY:${NC}"
        echo -n "> "
        read -s B2_APPLICATION_KEY
        echo ""
        while [ -z "$B2_APPLICATION_KEY" ]; do
            echo -e "${RED}❌ Não pode ser vazio!${NC}"
            echo -n "> "
            read -s B2_APPLICATION_KEY
            echo ""
        done
        B2_USE_SEPARATE_KEYS=false
        B2_DATA_KEY=""
        B2_CONFIG_KEY=""
    fi

    echo -e "${YELLOW}B2_BUCKET (ex: n8n-backups-offsite):${NC}"
    echo -n "> "
    read B2_BUCKET
    B2_BUCKET=${B2_BUCKET:-n8n-backups-offsite}

    echo -e "${YELLOW}B2_CONFIG_BUCKET (ex: n8n-config-offsite):${NC}"
    echo -n "> "
    read B2_CONFIG_BUCKET
    B2_CONFIG_BUCKET=${B2_CONFIG_BUCKET:-n8n-config-offsite}

    echo -e "${GREEN}✓ B2 configurado${NC}"

    # Storage para config (REMOVIDO - agora salva em ambos)
    # Sempre salva em Oracle E B2 para redundância
    CONFIG_STORAGE_TYPE="both"
    CONFIG_BUCKET="both"
    
    echo -e "${GREEN}✓ Configurações serão salvas em AMBOS os storages (redundância)${NC}"

    # Discord (opcional)
    echo ""
    echo -e "${YELLOW}Discord Webhook (opcional - ENTER para pular):${NC}"
    echo -n "> "
    read NOTIFY_WEBHOOK
}

# Funções Supabase
query_supabase() {
    local action="$1"
    local backup_key_hash="$2"
    local storage_type="${3:-}"
    local storage_config="${4:-}"

    local supabase_url="https://jpxctcxpxmevwiyaxkqu.supabase.co/functions/v1/backup-metadata"
    local backup_secret="xt6F2!iRMul*y9"

    local payload=""
    if [ "$action" = "get" ]; then
        payload="{\"action\":\"get\",\"backupKeyHash\":\"$backup_key_hash\"}"
    elif [ "$action" = "set" ]; then
        payload="{\"action\":\"set\",\"backupKeyHash\":\"$backup_key_hash\",\"storageType\":\"$storage_type\",\"storageConfig\":\"$storage_config\"}"
    fi

    curl -s -X POST "$supabase_url" \
         -H "Authorization: Bearer $backup_secret" \
         -H "Content-Type: application/json" \
         -d "$payload"
}

generate_backup_key_hash() {
    echo -n "$1" | sha256sum | awk '{print $1}'
}

save_metadata_to_supabase() {
    local backup_key_hash=$(generate_backup_key_hash "$BACKUP_MASTER_PASSWORD")

    # Criar metadados essenciais para acesso aos storages
    local metadata="ORACLE_CONFIG_BUCKET=\"$ORACLE_CONFIG_BUCKET\"
ORACLE_NAMESPACE=\"$ORACLE_NAMESPACE\"
ORACLE_REGION=\"$ORACLE_REGION\"
ORACLE_ACCESS_KEY=\"$ORACLE_ACCESS_KEY\"
ORACLE_SECRET_KEY=\"$ORACLE_SECRET_KEY\"
B2_CONFIG_BUCKET=\"$B2_CONFIG_BUCKET\"
B2_ACCOUNT_ID=\"$B2_ACCOUNT_ID\"
B2_APPLICATION_KEY=\"$B2_APPLICATION_KEY\"
B2_USE_SEPARATE_KEYS=\"$B2_USE_SEPARATE_KEYS\"
B2_DATA_KEY=\"$B2_DATA_KEY\"
B2_CONFIG_KEY=\"$B2_CONFIG_KEY\""

    # Criptografar metadados com a senha mestra
    local encrypted_metadata=$(echo "$metadata" | openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" 2>/dev/null | base64 | tr -d '\n')

    log_info "Salvando metadados criptografados no Supabase..."

    # DEBUG: Mostrar dados antes de enviar
    echo "DEBUG: backup_key_hash: $backup_key_hash"
    echo "DEBUG: encrypted_metadata length: ${#encrypted_metadata}"
    echo "DEBUG: encrypted_metadata preview: ${encrypted_metadata:0:50}..."

    # Enviar via query_supabase() - mais simples e consistente
    local response=$(query_supabase "set" "$backup_key_hash" "encrypted" "$encrypted_metadata")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        log_success "Metadados criptografados salvos"
        return 0
    else
        log_error "Falha ao salvar metadados: $response"
        return 1
    fi
}

load_metadata_from_supabase() {
    local master_password="$1"
    local backup_key_hash=$(generate_backup_key_hash "$master_password")

    log_info "Buscando metadados criptografados..."
    local response=$(query_supabase "get" "$backup_key_hash")

    if echo "$response" | jq -e '.storageType' > /dev/null 2>&1; then
        local storage_type=$(echo "$response" | jq -r '.storageType')
        local encrypted_data=$(echo "$response" | jq -r '.storageConfig')

    if [ "$storage_type" = "encrypted" ] && [ -n "$encrypted_data" ]; then
        log_info "Descriptografando metadados..."

        # DEBUG: Mostrar dados criptografados
        echo "DEBUG: encrypted_data (first 50): ${encrypted_data:0:50}"

        # Descriptografar metadados
        local decrypted_data=$(echo "$encrypted_data" | base64 -d | openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$master_password" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$decrypted_data" ]; then
            log_success "Metadados descriptografados"

            # DEBUG: Mostrar dados descriptografados
            echo "DEBUG: decrypted_data: $decrypted_data"

            # Carregar variáveis do metadado descriptografado
            eval "$decrypted_data"

                # Verificar se as variáveis essenciais foram carregadas
                if [ -n "$ORACLE_CONFIG_BUCKET" ] && [ -n "$B2_CONFIG_BUCKET" ]; then
                    log_success "Credenciais dos storages carregadas"
                    return 0
                else
                    log_error "Metadados incompletos"
                    return 1
                fi
            else
                log_error "Falha na descriptografia dos metadados"
                return 1
            fi
        else
            log_error "Formato de metadados inválido"
            return 1
        fi
    else
        log_warning "Metadados não encontrados: $response"
        return 1
    fi
}

# Salvar config criptografada
save_encrypted_config() {
    log_info "💾 Salvando configuração criptografada..."

    local temp_config="${SCRIPT_DIR}/temp_config.env"

    cat > "$temp_config" << EOF
N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY"
N8N_POSTGRES_PASSWORD="$N8N_POSTGRES_PASSWORD"
ORACLE_NAMESPACE="$ORACLE_NAMESPACE"
ORACLE_REGION="$ORACLE_REGION"
ORACLE_ACCESS_KEY="$ORACLE_ACCESS_KEY"
ORACLE_SECRET_KEY="$ORACLE_SECRET_KEY"
ORACLE_CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
ORACLE_BUCKET="$ORACLE_BUCKET"
B2_ACCOUNT_ID="$B2_ACCOUNT_ID"
B2_APPLICATION_KEY="$B2_APPLICATION_KEY"
B2_USE_SEPARATE_KEYS=$B2_USE_SEPARATE_KEYS
B2_DATA_KEY="$B2_DATA_KEY"
B2_CONFIG_KEY="$B2_CONFIG_KEY"
B2_CONFIG_BUCKET="$B2_CONFIG_BUCKET"
B2_BUCKET="$B2_BUCKET"
NOTIFY_WEBHOOK="$NOTIFY_WEBHOOK"
BACKUP_MASTER_PASSWORD="$BACKUP_MASTER_PASSWORD"
CONFIG_STORAGE_TYPE="$CONFIG_STORAGE_TYPE"
CONFIG_BUCKET="$CONFIG_BUCKET"
EOF

    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$temp_config" \
        -out "$ENCRYPTED_CONFIG_FILE"

    rm "$temp_config"
    upload_encrypted_config
    echo -e "${GREEN}✓ Configuração criptografada${NC}"
}

upload_encrypted_config() {
    log_info "📤 Enviando para storages (redundância)..."

    local uploaded_count=0

    # Upload para Oracle
    if [ "$ORACLE_ENABLED" = "true" ] && [ -n "$ORACLE_ACCESS_KEY" ]; then
        if rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${ORACLE_CONFIG_BUCKET}/" --quiet 2>/dev/null; then
            log_success "✓ Oracle"
            uploaded_count=$((uploaded_count + 1))
        else
            log_warning "✗ Oracle falhou"
        fi
    fi

    # Upload para B2
    if [ "$B2_ENABLED" = "true" ] && [ -n "$B2_ACCOUNT_ID" ]; then
        local b2_remote="b2"
        [ "$B2_USE_SEPARATE_KEYS" = "true" ] && b2_remote="b2-config"
        
        if rclone copy "$ENCRYPTED_CONFIG_FILE" "${b2_remote}:${B2_CONFIG_BUCKET}/" --quiet 2>/dev/null; then
            log_success "✓ B2 (offsite)"
            uploaded_count=$((uploaded_count + 1))
        else
            log_warning "✗ B2 falhou"
        fi
    fi

    if [ $uploaded_count -eq 0 ]; then
        log_error "❌ Nenhum storage funcionou!"
        return 1
    elif [ $uploaded_count -eq 1 ]; then
        log_warning "⚠️  Apenas 1 storage funcionou (sem redundância)"
    else
        log_success "✓ Configuração salva em $uploaded_count storages (redundante)"
    fi
}

# Carregar config do cloud (tenta ambos os storages)
load_encrypted_config() {
    echo ""
    echo -e "${BLUE}🔑 Digite sua senha mestra:${NC}"
    echo -n "> "
    read -s MASTER_PASSWORD
    echo ""

    [ -z "$MASTER_PASSWORD" ] && return 1

    log_info "📥 Buscando configuração..."

    # Primeiro tentar carregar metadados do Supabase para saber qual storage usar
    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        log_info "Metadados carregados do Supabase - configurando rclone..."

        # DEBUG: Verificar variáveis ANTES de gerar rclone
        echo "DEBUG: Antes do rclone - ORACLE_NAMESPACE=$ORACLE_NAMESPACE"

        # Gerar configuração rclone com as credenciais carregadas
        source "${SCRIPT_DIR}/lib/generate-rclone.sh"
        generate_rclone_config

        log_success "Rclone configurado com credenciais do Supabase"
    else
        log_warning "Metadados não encontrados no Supabase, tentando storages diretamente"
        # Fallback: tentar buckets padrão
        CONFIG_STORAGE_TYPE="both"
        CONFIG_BUCKET="both"
    fi

    # Tentar baixar de qualquer storage disponível
    local found=false

    # Tentar Oracle primeiro
    if rclone ls "oracle:" > /dev/null 2>&1; then
        echo "DEBUG: Tentando Oracle..."
        if rclone copy "oracle:${ORACLE_CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet 2>/dev/null; then
            log_info "Encontrado no Oracle"
            found=true
        else
            echo "DEBUG: Oracle falhou"
        fi
    else
        echo "DEBUG: Oracle não disponível"
    fi

    # Se não achou, tentar B2
    if [ "$found" = false ] && rclone ls "b2:" > /dev/null 2>&1; then
        echo "DEBUG: Tentando B2..."
        local b2_remote="b2"
        [ "$B2_USE_SEPARATE_KEYS" = "true" ] && b2_remote="b2-config"
        echo "DEBUG: b2_remote=$b2_remote, B2_CONFIG_BUCKET=$B2_CONFIG_BUCKET"
        if rclone copy "${b2_remote}:${B2_CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet 2>/dev/null; then
            log_info "Encontrado no B2"
            found=true
        else
            echo "DEBUG: B2 falhou"
        fi
    else
        echo "DEBUG: B2 não disponível ou já encontrado"
    fi

    # DEBUG: Verificar se arquivo foi baixado
    echo "DEBUG: Verificando se arquivo foi baixado..."
    echo "DEBUG: found=$found"
    echo "DEBUG: SCRIPT_DIR: $SCRIPT_DIR"
    echo "DEBUG: Permissões do diretório:"
    ls -ld "$SCRIPT_DIR"
    echo "DEBUG: Arquivos no diretório:"
    ls -la "${SCRIPT_DIR}/config.enc" 2>/dev/null || echo "DEBUG: Arquivo config.enc não existe no diretório"

    if [ "$found" = false ]; then
        log_warning "Config não encontrada nos storages"
        return 1
    fi

    # Descriptografar
    if [ -f "$ENCRYPTED_CONFIG_FILE" ]; then
        echo "DEBUG: Arquivo encontrado: $ENCRYPTED_CONFIG_FILE"
        echo "DEBUG: Tamanho do arquivo: $(stat -c%s "$ENCRYPTED_CONFIG_FILE" 2>/dev/null || echo 'N/A')"
        echo "DEBUG: Executando descriptografia..."

        local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
        openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$MASTER_PASSWORD" \
            -in "$ENCRYPTED_CONFIG_FILE" \
            -out "$temp_decrypted" 2>/dev/null

        local openssl_exit_code=$?
        echo "DEBUG: Código de saída openssl: $openssl_exit_code"

        if [ $openssl_exit_code -eq 0 ]; then
            echo "DEBUG: Descriptografia bem-sucedida, carregando variáveis..."
            source "$temp_decrypted"
            BACKUP_MASTER_PASSWORD="$MASTER_PASSWORD"
            rm "$temp_decrypted"
            echo -e "${GREEN}✓ Configuração carregada do cloud!${NC}"
            return 0
        else
            echo "DEBUG: Falha na descriptografia"
            echo -e "${RED}❌ Senha incorreta ou arquivo corrompido!${NC}"
            rm "$temp_decrypted" 2>/dev/null
        fi
    else
        echo "DEBUG: Arquivo $ENCRYPTED_CONFIG_FILE não encontrado"
    fi
    
    return 1
}

# Aplicar no config.env
apply_config_to_env() {
    log_info "📝 Aplicando no config.env..."
    
    sed -i "s|N8N_ENCRYPTION_KEY=\".*\"|N8N_ENCRYPTION_KEY=\"$N8N_ENCRYPTION_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|N8N_POSTGRES_PASSWORD=\".*\"|N8N_POSTGRES_PASSWORD=\"$N8N_POSTGRES_PASSWORD\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_NAMESPACE=\".*\"|ORACLE_NAMESPACE=\"$ORACLE_NAMESPACE\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_REGION=\".*\"|ORACLE_REGION=\"$ORACLE_REGION\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_ACCESS_KEY=\".*\"|ORACLE_ACCESS_KEY=\"$ORACLE_ACCESS_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_SECRET_KEY=\".*\"|ORACLE_SECRET_KEY=\"$ORACLE_SECRET_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_BUCKET=\".*\"|ORACLE_BUCKET=\"$ORACLE_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_CONFIG_BUCKET=\".*\"|ORACLE_CONFIG_BUCKET=\"$ORACLE_CONFIG_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_ACCOUNT_ID=\".*\"|B2_ACCOUNT_ID=\"$B2_ACCOUNT_ID\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_APPLICATION_KEY=\".*\"|B2_APPLICATION_KEY=\"$B2_APPLICATION_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_USE_SEPARATE_KEYS=.*|B2_USE_SEPARATE_KEYS=$B2_USE_SEPARATE_KEYS|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_DATA_KEY=\".*\"|B2_DATA_KEY=\"$B2_DATA_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_CONFIG_KEY=\".*\"|B2_CONFIG_KEY=\"$B2_CONFIG_KEY\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_BUCKET=\".*\"|B2_BUCKET=\"$B2_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_CONFIG_BUCKET=\".*\"|B2_CONFIG_BUCKET=\"$B2_CONFIG_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|BACKUP_MASTER_PASSWORD=\".*\"|BACKUP_MASTER_PASSWORD=\"$BACKUP_MASTER_PASSWORD\"|" "${SCRIPT_DIR}/config.env"
    [ -n "$NOTIFY_WEBHOOK" ] && sed -i "s|NOTIFY_WEBHOOK=\"\"|NOTIFY_WEBHOOK=\"$NOTIFY_WEBHOOK\"|" "${SCRIPT_DIR}/config.env"
    
    log_success "✓ config.env atualizado"
}

# Setup interativo
interactive_setup() {
    echo ""
    echo -e "${BLUE}🚀 N8N Backup System - Setup v4.0${NC}"
    echo -e "${BLUE}====================================${NC}"

    detect_credentials

    # TENTAR CARREGAR CONFIG DO CLOUD
    if load_encrypted_config; then
        # Sucesso - já tem tudo
        apply_config_to_env
        
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    CONFIGURAÇÃO CARREGADA! 🎉         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "🎯 Sistema pronto!"
        echo "   sudo ./n8n-backup.sh backup"
        return 0
    fi

    # NÃO ACHOU - PRIMEIRA INSTALAÇÃO
    echo -e "${YELLOW}⚠ Primeira instalação detectada${NC}"
    ask_all_credentials
    apply_config_to_env
    
    log_info "Gerando rclone..."
    source "${SCRIPT_DIR}/lib/generate-rclone.sh"
    generate_rclone_config

    save_encrypted_config
    save_metadata_to_supabase

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    CONFIGURAÇÃO CONCLUÍDA! 🎉         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "🎯 Próximo passo:"
    echo "   sudo ./n8n-backup.sh backup"
}

# Modo de edição - permite alterar configurações específicas
edit_mode() {
    echo ""
    echo -e "${BLUE}🔧 Modo de Edição${NC}"
    echo -e "${BLUE}=================${NC}"
    
    # Tentar carregar configuração atual
    if ! load_encrypted_config; then
        echo -e "${RED}❌ Não foi possível carregar configuração${NC}"
        echo "Execute primeiro: ./lib/setup.sh interactive"
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}✓ Configuração carregada${NC}"
    echo ""
    echo -e "${CYAN}Valores atuais:${NC}"
    echo "1)  N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY:0:10}...${N8N_ENCRYPTION_KEY: -10}"
    echo "2)  N8N_POSTGRES_PASSWORD: ${N8N_POSTGRES_PASSWORD:0:4}***"
    echo "3)  ORACLE_NAMESPACE: $ORACLE_NAMESPACE"
    echo "4)  ORACLE_REGION: $ORACLE_REGION"
    echo "5)  ORACLE_ACCESS_KEY: ${ORACLE_ACCESS_KEY:0:8}..."
    echo "6)  ORACLE_SECRET_KEY: ${ORACLE_SECRET_KEY:0:4}***${ORACLE_SECRET_KEY: -4}"
    echo "7)  ORACLE_BUCKET: $ORACLE_BUCKET"
    echo "8)  ORACLE_CONFIG_BUCKET: $ORACLE_CONFIG_BUCKET"
    echo "9)  B2_ACCOUNT_ID: $B2_ACCOUNT_ID"
    echo "10) B2_APPLICATION_KEY: ${B2_APPLICATION_KEY:0:4}***"
    echo "11) B2_USE_SEPARATE_KEYS: $B2_USE_SEPARATE_KEYS"
    echo "12) B2_BUCKET: $B2_BUCKET"
    echo "13) B2_CONFIG_BUCKET: $B2_CONFIG_BUCKET"
    echo "14) NOTIFY_WEBHOOK: ${NOTIFY_WEBHOOK:-<vazio>}"
    echo "15) CONFIG_STORAGE_TYPE: $CONFIG_STORAGE_TYPE"
    echo ""
    echo "0)  Salvar alterações e sair"
    echo ""
    
    while true; do
        echo -e "${YELLOW}Qual campo deseja editar? (0 para sair)${NC}"
        echo -n "> "
        read choice
        
        case $choice in
            0)
                echo ""
                echo -e "${YELLOW}Salvando alterações...${NC}"
                apply_config_to_env
                
                log_info "Regenerando rclone..."
                source "${SCRIPT_DIR}/lib/generate-rclone.sh"
                generate_rclone_config
                
                save_encrypted_config
                save_metadata_to_supabase
                
                echo -e "${GREEN}✓ Configuração atualizada!${NC}"
                break
                ;;
            1)
                echo -e "${YELLOW}Novo N8N_ENCRYPTION_KEY:${NC}"
                echo -n "> "
                read N8N_ENCRYPTION_KEY
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            2)
                echo -e "${YELLOW}Novo N8N_POSTGRES_PASSWORD:${NC}"
                echo -n "> "
                read -s N8N_POSTGRES_PASSWORD
                echo ""
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            3)
                echo -e "${YELLOW}Novo ORACLE_NAMESPACE:${NC}"
                echo -n "> "
                read ORACLE_NAMESPACE
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            4)
                echo -e "${YELLOW}Novo ORACLE_REGION:${NC}"
                echo -n "> "
                read ORACLE_REGION
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            5)
                echo -e "${YELLOW}Novo ORACLE_ACCESS_KEY:${NC}"
                echo -n "> "
                read ORACLE_ACCESS_KEY
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            6)
                echo -e "${YELLOW}Novo ORACLE_SECRET_KEY:${NC}"
                echo -n "> "
                read -s ORACLE_SECRET_KEY
                echo ""
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            7)
                echo -e "${YELLOW}Novo ORACLE_BUCKET:${NC}"
                echo -n "> "
                read ORACLE_BUCKET
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            8)
                echo -e "${YELLOW}Novo ORACLE_CONFIG_BUCKET:${NC}"
                echo -n "> "
                read ORACLE_CONFIG_BUCKET
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            9)
                echo -e "${YELLOW}Novo B2_ACCOUNT_ID:${NC}"
                echo -n "> "
                read B2_ACCOUNT_ID
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            10)
                echo -e "${YELLOW}Novo B2_APPLICATION_KEY:${NC}"
                echo -n "> "
                read -s B2_APPLICATION_KEY
                echo ""
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            11)
                echo -e "${YELLOW}B2_USE_SEPARATE_KEYS (true/false):${NC}"
                echo -n "> "
                read B2_USE_SEPARATE_KEYS
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            12)
                echo -e "${YELLOW}Novo B2_BUCKET:${NC}"
                echo -n "> "
                read B2_BUCKET
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            13)
                echo -e "${YELLOW}Novo B2_CONFIG_BUCKET:${NC}"
                echo -n "> "
                read B2_CONFIG_BUCKET
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            14)
                echo -e "${YELLOW}Novo NOTIFY_WEBHOOK:${NC}"
                echo -n "> "
                read NOTIFY_WEBHOOK
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            15)
                echo -e "${YELLOW}Novo CONFIG_STORAGE_TYPE (oracle/b2):${NC}"
                echo -n "> "
                read CONFIG_STORAGE_TYPE
                if [ "$CONFIG_STORAGE_TYPE" = "oracle" ]; then
                    CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
                else
                    CONFIG_BUCKET="$B2_CONFIG_BUCKET"
                fi
                echo -e "${GREEN}✓ Atualizado${NC}"
                ;;
            *)
                echo -e "${RED}❌ Opção inválida${NC}"
                ;;
        esac
        
        echo ""
    done
}

# Função principal
main() {
    case "${1:-interactive}" in
        interactive)
            interactive_setup
            ;;
        edit)
            edit_mode
            ;;
        detect)
            detect_credentials
            ;;
        *)
            echo "Uso: $0 {interactive|edit|detect}"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
