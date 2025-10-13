#!/bin/bash
# ============================================
# Configuração Automática e Interativa
# Arquivo: /opt/n8n-backup/lib/setup.sh
# Versão: 3.0 - Com sugestões de valores padrão
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

# Função auxiliar para pedir input com valor padrão
ask_with_default() {
    local prompt=$1
    local default=$2
    local secret=${3:-false}
    local result=""
    
    if [ -n "$default" ] && [ "$default" != "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ] && [ "$default" != "ALTERAR_COM_SUA_SENHA_POSTGRES_REAL" ] && [[ ! "$default" =~ ^ALTERAR_ ]]; then
        # Mostrar valor atual (mascarado se for secret)
        if [ "$secret" = true ]; then
            local masked="${default:0:4}***${default: -4}"
            echo -e "${YELLOW}${prompt}${NC}"
            echo -e "${CYAN}  [Atual: ${masked}] (pressione ENTER para manter)${NC}"
        else
            echo -e "${YELLOW}${prompt}${NC}"
            echo -e "${CYAN}  [Atual: ${default}] (pressione ENTER para manter)${NC}"
        fi
        echo -n "> "
        
        if [ "$secret" = true ]; then
            read -s result
            echo ""
        else
            read result
        fi
        
        # Se vazio, usar padrão
        if [ -z "$result" ]; then
            result="$default"
        fi
    else
        # Não tem valor padrão, pedir normalmente
        echo -e "${YELLOW}${prompt}${NC}"
        echo -n "> "
        
        if [ "$secret" = true ]; then
            read -s result
            echo ""
        else
            read result
        fi
    fi
    
    echo "$result"
}

# Função para detectar credenciais automaticamente
detect_credentials() {
    log_info "🔍 Detectando credenciais automaticamente..."

    # Carregar config.env para ver se já temos credenciais
    if [ -f "${SCRIPT_DIR}/config.env" ]; then
        source "${SCRIPT_DIR}/config.env"
    fi

    # Detectar N8N Encryption Key
    if [ -z "$N8N_ENCRYPTION_KEY" ] || [[ "$N8N_ENCRYPTION_KEY" =~ ^ALTERAR_ ]]; then
        N8N_CONTAINER=$(sudo docker ps --filter "name=n8n" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
        if [ -n "$N8N_CONTAINER" ]; then
            DETECTED_N8N_KEY=$(sudo docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
            if [ -n "$DETECTED_N8N_KEY" ]; then
                N8N_ENCRYPTION_KEY="$DETECTED_N8N_KEY"
                echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY detectada do container: ${N8N_CONTAINER}${NC}"
            fi
        fi
    fi

    # Detectar PostgreSQL Password
    if [ -z "$N8N_POSTGRES_PASSWORD" ] || [[ "$N8N_POSTGRES_PASSWORD" =~ ^ALTERAR_ ]]; then
        POSTGRES_CONTAINER=$(sudo docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "postgres" | head -1 || echo "")
        if [ -n "$POSTGRES_CONTAINER" ]; then
            DETECTED_POSTGRES_PASS=$(sudo docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
            if [ -n "$DETECTED_POSTGRES_PASS" ]; then
                N8N_POSTGRES_PASSWORD="$DETECTED_POSTGRES_PASS"
                echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD detectada do container: ${POSTGRES_CONTAINER}${NC}"
            fi
        fi
    fi
}

# Função para perguntar credenciais interativamente
ask_credentials() {
    echo ""
    echo -e "${BLUE}🔐 Configuração de Credenciais${NC}"
    echo -e "${BLUE}================================${NC}"

    # Senha mestra (sempre pedir nova)
    while true; do
        echo ""
        echo -e "${YELLOW}Digite uma senha mestra forte (mínimo 12 caracteres):${NC}"
        echo -e "${YELLOW}Esta senha protege todas as suas credenciais!${NC}"
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

        echo ""
        echo -e "${YELLOW}Confirme a senha mestra:${NC}"
        echo -n "> "
        read -s CONFIRM_PASSWORD
        echo ""

        if [ "$BACKUP_MASTER_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
            echo -e "${RED}❌ As senhas não coincidem!${NC}"
            BACKUP_MASTER_PASSWORD=""
            continue
        fi

        echo -e "${GREEN}✓ Senha mestra aceita (${#BACKUP_MASTER_PASSWORD} caracteres)${NC}"
        break
    done

    # N8N Encryption Key
    echo ""
    N8N_ENCRYPTION_KEY=$(ask_with_default "N8N_ENCRYPTION_KEY (encontre no EasyPanel > Settings > Encryption):" "$N8N_ENCRYPTION_KEY" false)
    while [ -z "$N8N_ENCRYPTION_KEY" ]; do
        echo -e "${RED}❌ Encryption key não pode ser vazia!${NC}"
        N8N_ENCRYPTION_KEY=$(ask_with_default "N8N_ENCRYPTION_KEY:" "" false)
    done
    echo -e "${GREEN}✓ Encryption key configurada${NC}"

    # PostgreSQL Password
    echo ""
    N8N_POSTGRES_PASSWORD=$(ask_with_default "N8N_POSTGRES_PASSWORD (senha do banco PostgreSQL):" "$N8N_POSTGRES_PASSWORD" false)
    while [ -z "$N8N_POSTGRES_PASSWORD" ]; do
        echo -e "${RED}❌ Senha PostgreSQL não pode ser vazia!${NC}"
        N8N_POSTGRES_PASSWORD=$(ask_with_default "N8N_POSTGRES_PASSWORD:" "" false)
    done
    echo -e "${GREEN}✓ PostgreSQL password configurada${NC}"

    # Oracle Credentials
    echo ""
    echo -e "${BLUE}Oracle Object Storage (S3-compatible):${NC}"
    
    ORACLE_NAMESPACE=$(ask_with_default "ORACLE_NAMESPACE (ex: axqwerty12345):" "${ORACLE_NAMESPACE:-}" false)
    while [ -z "$ORACLE_NAMESPACE" ]; do
        echo -e "${RED}❌ Namespace não pode ser vazio!${NC}"
        ORACLE_NAMESPACE=$(ask_with_default "ORACLE_NAMESPACE:" "" false)
    done

    ORACLE_REGION=$(ask_with_default "ORACLE_REGION (ex: eu-madrid-1):" "${ORACLE_REGION:-eu-madrid-1}" false)
    while [ -z "$ORACLE_REGION" ]; do
        echo -e "${RED}❌ Region não pode ser vazia!${NC}"
        ORACLE_REGION=$(ask_with_default "ORACLE_REGION:" "eu-madrid-1" false)
    done

    ORACLE_ACCESS_KEY=$(ask_with_default "ORACLE_ACCESS_KEY (Customer Secret Key - Access Key):" "${ORACLE_ACCESS_KEY:-}" false)
    while [ -z "$ORACLE_ACCESS_KEY" ]; do
        echo -e "${RED}❌ Access Key não pode ser vazia!${NC}"
        ORACLE_ACCESS_KEY=$(ask_with_default "ORACLE_ACCESS_KEY:" "" false)
    done

    ORACLE_SECRET_KEY=$(ask_with_default "ORACLE_SECRET_KEY (Customer Secret Key - Secret):" "${ORACLE_SECRET_KEY:-}" true)
    while [ -z "$ORACLE_SECRET_KEY" ]; do
        echo -e "${RED}❌ Secret Key não pode ser vazia!${NC}"
        ORACLE_SECRET_KEY=$(ask_with_default "ORACLE_SECRET_KEY:" "" true)
    done

    echo ""
    echo -e "${BLUE}Oracle Buckets:${NC}"
    
    ORACLE_BUCKET=$(ask_with_default "ORACLE_BUCKET (bucket para backups de DADOS):" "${ORACLE_BUCKET:-n8n-backups}" false)
    while [ -z "$ORACLE_BUCKET" ]; do
        echo -e "${RED}❌ Bucket de dados não pode ser vazio!${NC}"
        ORACLE_BUCKET=$(ask_with_default "ORACLE_BUCKET:" "n8n-backups" false)
    done

    ORACLE_CONFIG_BUCKET=$(ask_with_default "ORACLE_CONFIG_BUCKET (bucket para CONFIGURAÇÕES):" "${ORACLE_CONFIG_BUCKET:-n8n-config}" false)
    while [ -z "$ORACLE_CONFIG_BUCKET" ]; do
        echo -e "${RED}❌ Bucket de config não pode ser vazio!${NC}"
        ORACLE_CONFIG_BUCKET=$(ask_with_default "ORACLE_CONFIG_BUCKET:" "n8n-config" false)
    done
    
    echo -e "${GREEN}✓ Oracle credentials configuradas${NC}"

    # B2 Credentials
    echo ""
    echo -e "${BLUE}Backblaze B2:${NC}"
    
    B2_ACCOUNT_ID=$(ask_with_default "B2_ACCOUNT_ID:" "${B2_ACCOUNT_ID:-}" false)
    while [ -z "$B2_ACCOUNT_ID" ]; do
        echo -e "${RED}❌ Account ID não pode ser vazio!${NC}"
        B2_ACCOUNT_ID=$(ask_with_default "B2_ACCOUNT_ID:" "" false)
    done

    # Perguntar sobre chaves separadas
    echo ""
    echo -e "${YELLOW}Suas Application Keys B2 são específicas por bucket?${NC}"
    echo "1) Não - Tenho uma Master Application Key (acessa todos os buckets)"
    echo "2) Sim - Tenho Application Keys diferentes para cada bucket"
    echo -n "> Opção (1 ou 2) [1]: "
    read B2_KEY_TYPE
    B2_KEY_TYPE=${B2_KEY_TYPE:-1}

    case $B2_KEY_TYPE in
        1)
            B2_APPLICATION_KEY=$(ask_with_default "B2_APPLICATION_KEY (Master Key):" "${B2_APPLICATION_KEY:-}" true)
            while [ -z "$B2_APPLICATION_KEY" ]; do
                echo -e "${RED}❌ Application Key não pode ser vazia!${NC}"
                B2_APPLICATION_KEY=$(ask_with_default "B2_APPLICATION_KEY:" "" true)
            done
            B2_USE_SEPARATE_KEYS=false
            B2_DATA_KEY=""
            B2_CONFIG_KEY=""
            ;;
        2)
            echo ""
            echo -e "${BLUE}Application Key para bucket de DADOS:${NC}"
            B2_DATA_KEY=$(ask_with_default "B2_DATA_KEY (para backups):" "${B2_DATA_KEY:-}" true)
            while [ -z "$B2_DATA_KEY" ]; do
                echo -e "${RED}❌ Data Key não pode ser vazia!${NC}"
                B2_DATA_KEY=$(ask_with_default "B2_DATA_KEY:" "" true)
            done

            echo ""
            echo -e "${BLUE}Application Key para bucket de CONFIGURAÇÕES:${NC}"
            B2_CONFIG_KEY=$(ask_with_default "B2_CONFIG_KEY (para configurações):" "${B2_CONFIG_KEY:-}" true)
            while [ -z "$B2_CONFIG_KEY" ]; do
                echo -e "${RED}❌ Config Key não pode ser vazia!${NC}"
                B2_CONFIG_KEY=$(ask_with_default "B2_CONFIG_KEY:" "" true)
            done
            
            B2_USE_SEPARATE_KEYS=true
            B2_APPLICATION_KEY=""
            ;;
        *)
            echo -e "${YELLOW}⚠ Opção inválida. Assumindo Master Key.${NC}"
            B2_APPLICATION_KEY=$(ask_with_default "B2_APPLICATION_KEY:" "${B2_APPLICATION_KEY:-}" true)
            while [ -z "$B2_APPLICATION_KEY" ]; do
                echo -e "${RED}❌ Application Key não pode ser vazia!${NC}"
                B2_APPLICATION_KEY=$(ask_with_default "B2_APPLICATION_KEY:" "" true)
            done
            B2_USE_SEPARATE_KEYS=false
            ;;
    esac

    echo ""
    echo -e "${BLUE}B2 Buckets:${NC}"

    B2_BUCKET=$(ask_with_default "B2_BUCKET (bucket para backups de DADOS):" "${B2_BUCKET:-n8n-backups-offsite}" false)
    while [ -z "$B2_BUCKET" ]; do
        echo -e "${RED}❌ Bucket de dados não pode ser vazio!${NC}"
        B2_BUCKET=$(ask_with_default "B2_BUCKET:" "n8n-backups-offsite" false)
    done

    B2_CONFIG_BUCKET=$(ask_with_default "B2_CONFIG_BUCKET (bucket para CONFIGURAÇÕES):" "${B2_CONFIG_BUCKET:-n8n-config-offsite}" false)
    while [ -z "$B2_CONFIG_BUCKET" ]; do
        echo -e "${RED}❌ Bucket de config não pode ser vazio!${NC}"
        B2_CONFIG_BUCKET=$(ask_with_default "B2_CONFIG_BUCKET:" "n8n-config-offsite" false)
    done
    
    echo -e "${GREEN}✓ B2 credentials configuradas${NC}"

    # Escolher storage
    echo ""
    echo -e "${BLUE}Escolha o storage para salvar as configurações:${NC}"
    echo "1) Oracle Object Storage"
    echo "2) Backblaze B2"
    echo -n "> Opção (1 ou 2) [1]: "
    read STORAGE_CHOICE
    STORAGE_CHOICE=${STORAGE_CHOICE:-1}

    case $STORAGE_CHOICE in
        1)
            CONFIG_STORAGE_TYPE="oracle"
            CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
            ;;
        2)
            CONFIG_STORAGE_TYPE="b2"
            CONFIG_BUCKET="$B2_CONFIG_BUCKET"
            ;;
        *)
            echo -e "${YELLOW}⚠ Opção inválida. Usando Oracle por padrão.${NC}"
            CONFIG_STORAGE_TYPE="oracle"
            CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
            ;;
    esac

    # Discord Webhook (opcional)
    echo ""
    NOTIFY_WEBHOOK=$(ask_with_default "Discord Webhook (opcional - pressione ENTER para pular):" "${NOTIFY_WEBHOOK:-}" false)
    if [ -n "$NOTIFY_WEBHOOK" ]; then
        echo -e "${GREEN}✓ Discord webhook configurado${NC}"
    fi
}

# [Resto das funções permanecem iguais: query_supabase, generate_backup_key_hash, etc.]
# ... (código anterior continua aqui)

# Função para consultar Supabase
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
        payload="{\"action\":\"set\",\"backupKeyHash\":\"$backup_key_hash\",\"storageType\":\"$storage_type\",\"storageConfig\":$storage_config}"
    fi

    curl -s -X POST "$supabase_url" \
         -H "Authorization: Bearer $backup_secret" \
         -H "Content-Type: application/json" \
         -d "$payload"
}

generate_backup_key_hash() {
    local master_password="$1"
    echo -n "$master_password" | sha256sum | awk '{print $1}'
}

save_metadata_to_supabase() {
    local master_password="$1"
    local storage_type="$2"
    local config_bucket="$3"

    local backup_key_hash=$(generate_backup_key_hash "$master_password")

    local storage_config=""
    if [ "$storage_type" = "oracle" ]; then
        storage_config="{\"bucket\":\"$config_bucket\",\"namespace\":\"$ORACLE_NAMESPACE\"}"
    elif [ "$storage_type" = "b2" ]; then
        storage_config="{\"bucket\":\"$config_bucket\"}"
    fi

    log_info "Salvando metadados no Supabase..."
    local response=$(query_supabase "set" "$backup_key_hash" "$storage_type" "$storage_config")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        log_success "Metadados salvos no Supabase"
        return 0
    else
        log_error "Falha ao salvar metadados: $response"
        return 1
    fi
}

load_metadata_from_supabase() {
    local master_password="$1"
    local backup_key_hash=$(generate_backup_key_hash "$master_password")

    log_info "Buscando metadados no Supabase..."
    local response=$(query_supabase "get" "$backup_key_hash")

    if echo "$response" | jq -e '.storageType' > /dev/null 2>&1; then
        CONFIG_STORAGE_TYPE=$(echo "$response" | jq -r '.storageType')
        CONFIG_BUCKET=$(echo "$response" | jq -r '.storageConfig.bucket')
        log_success "Metadados carregados do Supabase"
        return 0
    else
        log_info "Metadados não encontrados (primeira instalação)"
        return 1
    fi
}

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
B2_APPLICATION_KEY="${B2_APPLICATION_KEY:-}"
B2_USE_SEPARATE_KEYS="${B2_USE_SEPARATE_KEYS:-false}"
B2_DATA_KEY="${B2_DATA_KEY:-}"
B2_CONFIG_KEY="${B2_CONFIG_KEY:-}"
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
    echo -e "${GREEN}✓ Configuração salva e criptografada${NC}"
}

upload_encrypted_config() {
    log_info "Enviando configuração para ${CONFIG_STORAGE_TYPE}..."

    if [ "$CONFIG_STORAGE_TYPE" = "oracle" ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${CONFIG_BUCKET}/" --quiet && \
            log_success "Configuração enviada para Oracle"
    elif [ "$CONFIG_STORAGE_TYPE" = "b2" ]; then
        local b2_remote="b2"
        [ "$B2_USE_SEPARATE_KEYS" = true ] && b2_remote="b2-config"
        rclone copy "$ENCRYPTED_CONFIG_FILE" "${b2_remote}:${CONFIG_BUCKET}/" --quiet && \
            log_success "Configuração enviada para B2"
    fi
}

load_encrypted_config() {
    log_info "📥 Carregando configuração do cloud..."

    echo ""
    echo -e "${BLUE}🔑 Digite sua senha mestra:${NC}"
    echo -n "> "
    read -s MASTER_PASSWORD
    echo ""

    [ -z "$MASTER_PASSWORD" ] && return 1

    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        [ "$CONFIG_STORAGE_TYPE" = "oracle" ] && \
            rclone copy "oracle:${CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet
        [ "$CONFIG_STORAGE_TYPE" = "b2" ] && \
            rclone copy "b2:${CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet

        if [ -f "$ENCRYPTED_CONFIG_FILE" ]; then
            local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
            openssl enc -d -aes-256-cbc -salt -pbkdf2 \
                -pass pass:"$MASTER_PASSWORD" \
                -in "$ENCRYPTED_CONFIG_FILE" \
                -out "$temp_decrypted" 2>/dev/null

            if [ $? -eq 0 ]; then
                source "$temp_decrypted"
                BACKUP_MASTER_PASSWORD="$MASTER_PASSWORD"
                rm "$temp_decrypted"
                echo -e "${GREEN}✓ Configuração carregada!${NC}"
                return 0
            fi
        fi
    fi
    return 1
}

apply_config_to_env() {
    log_info "📝 Aplicando configuração no config.env..."
    sed -i "s|N8N_ENCRYPTION_KEY=\".*\"|N8N_ENCRYPTION_KEY=\"$N8N_ENCRYPTION_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|N8N_POSTGRES_PASSWORD=\".*\"|N8N_POSTGRES_PASSWORD=\"$N8N_POSTGRES_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_NAMESPACE=\".*\"|ORACLE_NAMESPACE=\"$ORACLE_NAMESPACE\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_REGION=\".*\"|ORACLE_REGION=\"$ORACLE_REGION\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_ACCESS_KEY=\".*\"|ORACLE_ACCESS_KEY=\"$ORACLE_ACCESS_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_SECRET_KEY=\".*\"|ORACLE_SECRET_KEY=\"$ORACLE_SECRET_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_CONFIG_BUCKET=\".*\"|ORACLE_CONFIG_BUCKET=\"$ORACLE_CONFIG_BUCKET\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_BUCKET=\".*\"|ORACLE_BUCKET=\"$ORACLE_BUCKET\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_ACCOUNT_ID=\".*\"|B2_ACCOUNT_ID=\"$B2_ACCOUNT_ID\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_APPLICATION_KEY=\".*\"|B2_APPLICATION_KEY=\"${B2_APPLICATION_KEY:-}\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_USE_SEPARATE_KEYS=.*|B2_USE_SEPARATE_KEYS=${B2_USE_SEPARATE_KEYS}|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_DATA_KEY=\".*\"|B2_DATA_KEY=\"${B2_DATA_KEY:-}\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_CONFIG_KEY=\".*\"|B2_CONFIG_KEY=\"${B2_CONFIG_KEY:-}\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_CONFIG_BUCKET=\".*\"|B2_CONFIG_BUCKET=\"$B2_CONFIG_BUCKET\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_BUCKET=\".*\"|B2_BUCKET=\"$B2_BUCKET\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|BACKUP_MASTER_PASSWORD=\".*\"|BACKUP_MASTER_PASSWORD=\"$BACKUP_MASTER_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"
    [ -n "$NOTIFY_WEBHOOK" ] && sed -i "s|NOTIFY_WEBHOOK=\"\"|NOTIFY_WEBHOOK=\"$NOTIFY_WEBHOOK\"|g" "${SCRIPT_DIR}/config.env"
    echo -e "${GREEN}✓ Configuração aplicada!${NC}"
}

interactive_setup() {
    echo ""
    echo -e "${BLUE}🚀 N8N Backup System - Configuração Interativa v3.0${NC}"
    echo -e "${BLUE}====================================================${NC}"

    detect_credentials

    if load_encrypted_config; then
        echo -e "${GREEN}✓ Configuração carregada do cloud!${NC}"
        apply_config_to_env
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    SISTEMA JÁ CONFIGURADO! 🎉         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Configuração não encontrada. Vamos configurar...${NC}"
        ask_credentials
    fi

    apply_config_to_env
    
    log_info "Gerando configuração rclone..."
    source "${SCRIPT_DIR}/lib/generate-rclone.sh"
    generate_rclone_config

    save_encrypted_config
    save_metadata_to_supabase "$BACKUP_MASTER_PASSWORD" "$CONFIG_STORAGE_TYPE" "$CONFIG_BUCKET"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    CONFIGURAÇÃO CONCLUÍDA! 🎉         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "🎯 Próximos passos:"
    echo "   sudo ./n8n-backup.sh backup"
    echo ""
}

main() {
    case "${1:-interactive}" in
        interactive) interactive_setup ;;
        detect) detect_credentials ;;
        save) save_encrypted_config ;;
        load) load_encrypted_config ;;
        *) echo "Uso: $0 {interactive|detect|save|load}"; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi