#!/bin/bash
# ============================================
# Configuração Automática e Interativa
# Arquivo: /opt/n8n-backup/lib/setup.sh
# Versão: 4.1 - Validação Robusta + Fallback Oracle→B2
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Diretório base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Carregar logger (cria se não existir)
if [ -f "${SCRIPT_DIR}/lib/logger.sh" ]; then
    source "${SCRIPT_DIR}/lib/logger.sh"
else
    log_info() { echo "[INFO] $@"; }
    log_success() { echo "[OK] $@"; }
    log_warning() { echo "[WARN] $@"; }
    log_error() { echo "[ERROR] $@"; }
fi

# Arquivo de configuração criptografada
ENCRYPTED_CONFIG_FILE="${SCRIPT_DIR}/config.enc"

# ========================================
# FUNÇÕES AUXILIARES PARA VALIDAÇÃO
# ========================================

# Verificar se arquivo existe no storage remoto
check_remote_file_exists() {
    local remote=$1
    local bucket=$2
    local filename=$3
    
    log_info "🔍 Verificando se $filename existe em $remote:$bucket/..."
    
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
    
    # Criar diretório pai se não existir
    mkdir -p "$(dirname $destination)"
    
    # Tentar download com timeout
    if timeout 60 rclone copy "${remote}:${bucket}/${filename}" "$(dirname $destination)/" --progress 2>&1 | tail -5; then
        
        # Verificar se arquivo foi criado
        if [ ! -f "$destination" ]; then
            log_error "❌ Download executado mas arquivo não foi salvo em: $destination"
            ls -la "$(dirname $destination)/" 2>&1 | head -10
            return 1
        fi
        
        # Verificar tamanho (deve ter pelo menos 100 bytes)
        local file_size=$(stat -c%s "$destination" 2>/dev/null || echo "0")
        
        if [ "$file_size" -lt 100 ]; then
            log_error "❌ Arquivo muito pequeno ($file_size bytes)"
            rm -f "$destination"
            return 1
        fi
        
        log_success "✅ Arquivo válido baixado ($file_size bytes)"
        return 0
        
    else
        log_error "❌ Falha no download de $remote"
        rm -f "$destination"
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

# ========================================
# FUNÇÕES SUPABASE
# ========================================

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

    local encrypted_metadata=$(echo "$metadata" | openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" 2>/dev/null | base64 | tr -d '\n')

    log_info "Salvando metadados criptografados no Supabase..."

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

            local decrypted_data=$(echo "$encrypted_data" | base64 -d | openssl enc -d -aes-256-cbc -salt -pbkdf2 \
                -pass pass:"$master_password" 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$decrypted_data" ]; then
                eval "$decrypted_data" 2>/dev/null || log_warning "Erro ao parsear variáveis"
                log_success "Metadados descriptografados"
                return 0
            else
                log_error "Falha ao descriptografar metadados"
                return 1
            fi
        fi
    fi

    log_warning "Metadados não encontrados"
    return 1
}

# ========================================
# CARREGAR CONFIG DO CLOUD (VERSÃO ROBUSTA)
# ========================================

load_encrypted_config() {
    echo ""
    echo -e "${BLUE}🔑 Digite sua senha mestra:${NC}"
    echo -n "> "
    read -s MASTER_PASSWORD
    echo ""

    [ -z "$MASTER_PASSWORD" ] && return 1

    log_info "📥 Buscando configuração nos storages..."
    echo ""

    # Garantir permissões
    mkdir -p "${SCRIPT_DIR}"
    chmod 755 "${SCRIPT_DIR}"

    # Tentar carregar metadados do Supabase
    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        log_info "📊 Metadados carregados do Supabase"
        
        # Gerar rclone.conf
        source "${SCRIPT_DIR}/lib/generate-rclone.sh"
        generate_rclone_config
        
        log_success "✅ Rclone configurado"
    else
        log_warning "⚠️  Metadados não encontrados no Supabase"
    fi

    echo ""
    log_info "🔍 Estratégia: Oracle → B2 → Nova Instalação"
    echo ""

    local config_loaded=false
    
    # ========================================
    # TENTATIVA 1: ORACLE
    # ========================================
    if [ "$ORACLE_ENABLED" = "true" ] && rclone listremotes 2>/dev/null | grep -q "oracle:"; then
        log_info "📦 [1/2] Tentando Oracle..."
        
        if check_remote_file_exists "oracle" "$ORACLE_CONFIG_BUCKET" "config.enc"; then
            if download_and_validate "oracle" "$ORACLE_CONFIG_BUCKET" "config.enc" "$ENCRYPTED_CONFIG_FILE"; then
                local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
                if try_decrypt "$ENCRYPTED_CONFIG_FILE" "$MASTER_PASSWORD" "$temp_decrypted"; then
                    source "$temp_decrypted"
                    apply_config_to_env
                    rm -f "$temp_decrypted" "$ENCRYPTED_CONFIG_FILE"
                    config_loaded=true
                    echo ""
                    log_success "🎉 Configuração carregada do Oracle!"
                    return 0
                fi
            fi
        fi
    else
        log_warning "⚠️  Oracle não disponível"
    fi

    echo ""
    
    # ========================================
    # TENTATIVA 2: B2 (FALLBACK)
    # ========================================
    if [ "$config_loaded" = false ] && [ "$B2_ENABLED" = "true" ]; then
        local b2_remote="b2"
        [ "$B2_USE_SEPARATE_KEYS" = "true" ] && b2_remote="b2-config"
        
        if rclone listremotes 2>/dev/null | grep -q "${b2_remote}:"; then
            log_info "📦 [2/2] Tentando B2 (fallback)..."
            
            if check_remote_file_exists "$b2_remote" "$B2_CONFIG_BUCKET" "config.enc"; then
                if download_and_validate "$b2_remote" "$B2_CONFIG_BUCKET" "config.enc" "$ENCRYPTED_CONFIG_FILE"; then
                    local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
                    if try_decrypt "$ENCRYPTED_CONFIG_FILE" "$MASTER_PASSWORD" "$temp_decrypted"; then
                        source "$temp_decrypted"
                        apply_config_to_env
                        rm -f "$temp_decrypted" "$ENCRYPTED_CONFIG_FILE"
                        config_loaded=true
                        echo ""
                        log_success "🎉 Configuração carregada do B2!"
                        
                        # Sincronizar para Oracle
                        if [ "$ORACLE_ENABLED" = "true" ]; then
                            log_warning "⚠️  Sincronizando B2 → Oracle..."
                            rclone copy "${b2_remote}:${B2_CONFIG_BUCKET}/config.enc" "oracle:${ORACLE_CONFIG_BUCKET}/" 2>/dev/null && \
                                log_success "✅ Oracle sincronizado" || \
                                log_warning "⚠️  Sincronização falhou (não crítico)"
                        fi
                        
                        return 0
                    fi
                fi
            fi
        else
            log_warning "⚠️  B2 não disponível"
        fi
    fi

    echo ""
    
    if [ "$config_loaded" = false ]; then
        log_warning "❌ Nenhuma configuração encontrada"
        log_info "📝 Iniciando nova instalação..."
        return 1
    fi
}

# ========================================
# DEMAIS FUNÇÕES (do original)
# ========================================

detect_credentials() {
    log_info "🔍 Detectando credenciais automaticamente..."

    N8N_CONTAINER=$(sudo docker ps --filter "name=n8n" --format "{{.Names}}" 2>/dev/null | grep -E "^n8n" | head -1 || echo "")
    if [ -n "$N8N_CONTAINER" ]; then
        DETECTED_N8N_KEY=$(sudo docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
        if [ -n "$DETECTED_N8N_KEY" ]; then
            N8N_ENCRYPTION_KEY="$DETECTED_N8N_KEY"
            echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY auto-detectada${NC}"
        fi
    fi

    POSTGRES_CONTAINER=$(sudo docker ps --filter "name=postgres" --format "{{.Names}}" 2>/dev/null | grep -E "postgres" | head -1 || echo "")
    if [ -n "$POSTGRES_CONTAINER" ]; then
        DETECTED_POSTGRES_PASS=$(sudo docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
        if [ -n "$DETECTED_POSTGRES_PASS" ]; then
            N8N_POSTGRES_PASSWORD="$DETECTED_POSTGRES_PASS"
            echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD auto-detectada${NC}"
        fi
    fi
}

ask_all_credentials() {
    echo ""
    echo -e "${BLUE}🔐 Configuração Completa (Primeira Instalação)${NC}"
    echo -e "${BLUE}================================================${NC}"

    # Senha mestra
    while true; do
        echo ""
        echo -e "${YELLOW}Crie uma senha mestra forte (mínimo 12 caracteres):${NC}"
        echo -n "> "
        read -s BACKUP_MASTER_PASSWORD
        echo ""

        [ -z "$BACKUP_MASTER_PASSWORD" ] && continue
        [ ${#BACKUP_MASTER_PASSWORD} -lt 12 ] && continue

        echo -e "${YELLOW}Confirme a senha mestra:${NC}"
        echo -n "> "
        read -s CONFIRM_PASSWORD
        echo ""

        [ "$BACKUP_MASTER_PASSWORD" != "$CONFIRM_PASSWORD" ] && continue
        
        echo -e "${GREEN}✓ Senha mestra criada${NC}"
        break
    done

    # N8N Encryption Key
    echo -e "${YELLOW}N8N_ENCRYPTION_KEY:${NC}"
    [ -n "$N8N_ENCRYPTION_KEY" ] && echo -e "${CYAN}(Auto-detectada - ENTER para usar)${NC}"
    read -p "> " INPUT_KEY
    [ -n "$INPUT_KEY" ] && N8N_ENCRYPTION_KEY="$INPUT_KEY"
    while [ -z "$N8N_ENCRYPTION_KEY" ]; do
        read -p "> " N8N_ENCRYPTION_KEY
    done

    # PostgreSQL Password
    echo -e "${YELLOW}N8N_POSTGRES_PASSWORD:${NC}"
    [ -n "$N8N_POSTGRES_PASSWORD" ] && echo -e "${CYAN}(Auto-detectada - ENTER para usar)${NC}"
    read -p "> " INPUT_PASS
    [ -n "$INPUT_PASS" ] && N8N_POSTGRES_PASSWORD="$INPUT_PASS"
    while [ -z "$N8N_POSTGRES_PASSWORD" ]; do
        read -p "> " N8N_POSTGRES_PASSWORD
    done

    # Oracle
    echo -e "${BLUE}Oracle Object Storage:${NC}"
    read -p "ORACLE_NAMESPACE: " ORACLE_NAMESPACE
    read -p "ORACLE_REGION [eu-madrid-1]: " ORACLE_REGION
    ORACLE_REGION=${ORACLE_REGION:-eu-madrid-1}
    read -p "ORACLE_ACCESS_KEY: " ORACLE_ACCESS_KEY
    read -sp "ORACLE_SECRET_KEY: " ORACLE_SECRET_KEY
    echo ""
    read -p "ORACLE_BUCKET [n8n-backups]: " ORACLE_BUCKET
    ORACLE_BUCKET=${ORACLE_BUCKET:-n8n-backups}
    read -p "ORACLE_CONFIG_BUCKET [n8n-config]: " ORACLE_CONFIG_BUCKET
    ORACLE_CONFIG_BUCKET=${ORACLE_CONFIG_BUCKET:-n8n-config}

    # B2
    echo -e "${BLUE}Backblaze B2:${NC}"
    read -p "B2_ACCOUNT_ID: " B2_ACCOUNT_ID
    read -sp "B2_APPLICATION_KEY: " B2_APPLICATION_KEY
    echo ""
    B2_USE_SEPARATE_KEYS=false
    read -p "B2_BUCKET [n8n-backups-offsite]: " B2_BUCKET
    B2_BUCKET=${B2_BUCKET:-n8n-backups-offsite}
    read -p "B2_CONFIG_BUCKET [n8n-config-offsite]: " B2_CONFIG_BUCKET
    B2_CONFIG_BUCKET=${B2_CONFIG_BUCKET:-n8n-config-offsite}

    # Discord
    read -p "Discord Webhook (opcional): " NOTIFY_WEBHOOK
}

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
    sed -i "s|B2_BUCKET=\".*\"|B2_BUCKET=\"$B2_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_CONFIG_BUCKET=\".*\"|B2_CONFIG_BUCKET=\"$B2_CONFIG_BUCKET\"|" "${SCRIPT_DIR}/config.env"
    sed -i "s|BACKUP_MASTER_PASSWORD=\".*\"|BACKUP_MASTER_PASSWORD=\"$BACKUP_MASTER_PASSWORD\"|" "${SCRIPT_DIR}/config.env"
    [ -n "$NOTIFY_WEBHOOK" ] && sed -i "s|NOTIFY_WEBHOOK=\"\"|NOTIFY_WEBHOOK=\"$NOTIFY_WEBHOOK\"|" "${SCRIPT_DIR}/config.env"
    
    log_success "✓ config.env atualizado"
}

save_encrypted_config() {
    log_info "Salvando configuração criptografada..."
    
    local temp_config="${SCRIPT_DIR}/temp_config.env"
    cat > "$temp_config" <<EOF
N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY"
N8N_POSTGRES_PASSWORD="$N8N_POSTGRES_PASSWORD"
ORACLE_NAMESPACE="$ORACLE_NAMESPACE"
ORACLE_REGION="$ORACLE_REGION"
ORACLE_ACCESS_KEY="$ORACLE_ACCESS_KEY"
ORACLE_SECRET_KEY="$ORACLE_SECRET_KEY"
ORACLE_BUCKET="$ORACLE_BUCKET"
ORACLE_CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
B2_ACCOUNT_ID="$B2_ACCOUNT_ID"
B2_APPLICATION_KEY="$B2_APPLICATION_KEY"
B2_USE_SEPARATE_KEYS="$B2_USE_SEPARATE_KEYS"
B2_BUCKET="$B2_BUCKET"
B2_CONFIG_BUCKET="$B2_CONFIG_BUCKET"
NOTIFY_WEBHOOK="$NOTIFY_WEBHOOK"
EOF

    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$temp_config" \
        -out "$ENCRYPTED_CONFIG_FILE" 2>/dev/null

    rm -f "$temp_config"

    # Upload para Oracle
    if [ "$ORACLE_ENABLED" = "true" ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${ORACLE_CONFIG_BUCKET}/" 2>/dev/null && \
            log_success "✓ Oracle" || log_warning "✗ Oracle falhou"
    fi

    # Upload para B2
    if [ "$B2_ENABLED" = "true" ]; then
        local b2_remote="b2"
        [ "$B2_USE_SEPARATE_KEYS" = "true" ] && b2_remote="b2-config"
        rclone copy "$ENCRYPTED_CONFIG_FILE" "${b2_remote}:${B2_CONFIG_BUCKET}/" 2>/dev/null && \
            log_success "✓ B2" || log_warning "✗ B2 falhou"
    fi
}

interactive_setup() {
    echo ""
    echo -e "${BLUE}🚀 N8N Backup System - Setup v4.1${NC}"
    echo -e "${BLUE}====================================${NC}"

    detect_credentials

    if load_encrypted_config; then
        apply_config_to_env
        
        echo ""
        echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    CONFIGURAÇÃO CARREGADA! 🎉         ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
        echo ""
        echo "🎯 Sistema pronto!"
        return 0
    fi

    echo -e "${YELLOW}⚠  Primeira instalação detectada${NC}"
    ask_all_credentials
    apply_config_to_env
    
    log_info "Gerando rclone..."
    source "${SCRIPT_DIR}/lib/generate-rclone.sh"
    generate_rclone_config

    save_encrypted_config
    save_metadata_to_supabase

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    CONFIGURAÇÃO CONCLUÍDA! 🎉         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════╝${NC}"
}

main() {
    case "${1:-interactive}" in
        interactive)
            interactive_setup
            ;;
        *)
            echo "Uso: $0 interactive"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi