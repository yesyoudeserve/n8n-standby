#!/bin/bash
# ============================================
# Configuração Automática e Interativa
# Arquivo: /opt/n8n-backup/lib/setup.sh
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Carregar funções do logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# Carregar funções de segurança
source "${SCRIPT_DIR}/lib/security.sh"

# Arquivo de configuração criptografada
ENCRYPTED_CONFIG_FILE="${SCRIPT_DIR}/config.enc"

# Função para detectar credenciais automaticamente
detect_credentials() {
    log_info "🔍 Detectando credenciais automaticamente..."

    # Detectar N8N Encryption Key (EasyPanel usa nomes dinâmicos)
    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ "$N8N_ENCRYPTION_KEY" = "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ]; then
        # Procurar container N8N principal (pode ter sufixo dinâmico)
        N8N_CONTAINER=$(sudo docker ps --filter "name=n8n" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
        if [ -n "$N8N_CONTAINER" ]; then
            DETECTED_N8N_KEY=$(sudo docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
            if [ -n "$DETECTED_N8N_KEY" ]; then
                N8N_ENCRYPTION_KEY="$DETECTED_N8N_KEY"
                echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY detectada automaticamente do container: ${N8N_CONTAINER}${NC}"
            fi
        fi
    fi

    # Detectar PostgreSQL Password (EasyPanel usa nomes dinâmicos)
    if [ -z "$N8N_POSTGRES_PASSWORD" ] || [ "$N8N_POSTGRES_PASSWORD" = "ALTERAR_COM_SUA_SENHA_POSTGRES_REAL" ]; then
        # Procurar container PostgreSQL (pode ter sufixo dinâmico)
        POSTGRES_CONTAINER=$(sudo docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "postgres" | head -1 || echo "")
        if [ -n "$POSTGRES_CONTAINER" ]; then
            DETECTED_POSTGRES_PASS=$(sudo docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
            if [ -n "$DETECTED_POSTGRES_PASS" ]; then
                N8N_POSTGRES_PASSWORD="$DETECTED_POSTGRES_PASS"
                echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD detectada automaticamente do container: ${POSTGRES_CONTAINER}${NC}"
            fi
        fi
    fi
}

# Função para perguntar credenciais interativamente
ask_credentials() {
    echo ""
    echo -e "${BLUE}🔐 Configuração de Credenciais${NC}"
    echo -e "${BLUE}================================${NC}"

    # Senha mestra (sempre pedir)
    while true; do
        echo ""
        echo -e "${YELLOW}Digite uma senha mestra forte (mínimo 12 caracteres):${NC}"
        echo -e "${YELLOW}Esta senha protege todas as suas credenciais!${NC}"
        echo -n "> "
        read -s BACKUP_MASTER_PASSWORD
        echo ""

        # Validar se não está vazia
        if [ -z "$BACKUP_MASTER_PASSWORD" ]; then
            echo -e "${RED}❌ Senha não pode ser vazia!${NC}"
            continue
        fi

        # Validar tamanho
        if [ ${#BACKUP_MASTER_PASSWORD} -lt 12 ]; then
            echo -e "${RED}❌ Senha muito curta! Mínimo 12 caracteres.${NC}"
            continue
        fi

        # Confirmar senha
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
    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ "$N8N_ENCRYPTION_KEY" = "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ]; then
        echo ""
        echo -e "${YELLOW}N8N_ENCRYPTION_KEY (encontre no EasyPanel > Settings > Encryption):${NC}"
        echo -n "> "
        read -s N8N_ENCRYPTION_KEY
        echo ""
        
        if [ -z "$N8N_ENCRYPTION_KEY" ]; then
            echo -e "${RED}❌ Encryption key não pode ser vazia!${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✓ Encryption key configurada${NC}"
    else
        echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY já detectada${NC}"
    fi

    # PostgreSQL Password
    if [ -z "$N8N_POSTGRES_PASSWORD" ] || [ "$N8N_POSTGRES_PASSWORD" = "ALTERAR_COM_SUA_SENHA_POSTGRES_REAL" ]; then
        echo ""
        echo -e "${YELLOW}N8N_POSTGRES_PASSWORD (senha do banco PostgreSQL):${NC}"
        echo -n "> "
        read -s N8N_POSTGRES_PASSWORD
        echo ""
        
        if [ -z "$N8N_POSTGRES_PASSWORD" ]; then
            echo -e "${RED}❌ Senha PostgreSQL não pode ser vazia!${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✓ PostgreSQL password configurada${NC}"
    else
        echo -e "${GREEN}✓ N8N_POSTGRES_PASSWORD já detectada${NC}"
    fi

    # Oracle Credentials
    echo ""
    echo -e "${BLUE}Oracle Object Storage:${NC}"
    
    if [ -z "$ORACLE_NAMESPACE" ] || [ "$ORACLE_NAMESPACE" = "ALTERAR_COM_SEU_NAMESPACE_REAL" ]; then
        echo -e "${YELLOW}ORACLE_NAMESPACE:${NC}"
        echo -n "> "
        read ORACLE_NAMESPACE
    fi

    if [ -z "$ORACLE_COMPARTMENT_ID" ] || [ "$ORACLE_COMPARTMENT_ID" = "ALTERAR_COM_SEU_COMPARTMENT_ID_REAL" ]; then
        echo -e "${YELLOW}ORACLE_COMPARTMENT_ID:${NC}"
        echo -n "> "
        read ORACLE_COMPARTMENT_ID
    fi

    # Bucket de configuração Oracle (separado dos dados)
    if [ -z "$ORACLE_CONFIG_BUCKET" ] || [ "$ORACLE_CONFIG_BUCKET" = "ALTERAR_COM_SEU_BUCKET_CONFIG_REAL" ]; then
        echo -e "${YELLOW}ORACLE_CONFIG_BUCKET (bucket dedicado para configurações):${NC}"
        echo -n "> "
        read ORACLE_CONFIG_BUCKET
    fi

    # B2 Credentials
    echo ""
    echo -e "${BLUE}Backblaze B2:${NC}"
    
    if [ -z "$B2_ACCOUNT_ID" ] || [ "$B2_ACCOUNT_ID" = "ALTERAR_COM_SEU_ACCOUNT_ID_REAL" ]; then
        echo -e "${YELLOW}B2_ACCOUNT_ID:${NC}"
        echo -n "> "
        read B2_ACCOUNT_ID
    fi

    if [ -z "$B2_APPLICATION_KEY" ] || [ "$B2_APPLICATION_KEY" = "ALTERAR_COM_SUA_APP_KEY_REAL" ]; then
        echo -e "${YELLOW}B2_APPLICATION_KEY:${NC}"
        echo -n "> "
        read -s B2_APPLICATION_KEY
        echo ""
    fi

    # Bucket de configuração B2 (separado dos dados)
    if [ -z "$B2_CONFIG_BUCKET" ] || [ "$B2_CONFIG_BUCKET" = "ALTERAR_COM_SEU_BUCKET_CONFIG_REAL" ]; then
        echo -e "${YELLOW}B2_CONFIG_BUCKET (bucket dedicado para configurações):${NC}"
        echo -n "> "
        read B2_CONFIG_BUCKET
        echo -e "${GREEN}✓ B2 credentials configuradas${NC}"
    fi

    # Escolher storage para configurações
    echo ""
    echo -e "${BLUE}Escolha o storage para salvar as configurações:${NC}"
    echo "1) Oracle Object Storage"
    echo "2) Backblaze B2"
    echo -n "> Opção (1 ou 2): "
    read STORAGE_CHOICE

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
    echo -e "${BLUE}Discord Webhook (opcional - pressione ENTER para pular):${NC}"
    if [ -z "$NOTIFY_WEBHOOK" ] || [ "$NOTIFY_WEBHOOK" = "ALTERAR_COM_SEU_WEBHOOK_DISCORD_REAL" ]; then
        echo -n "> "
        read NOTIFY_WEBHOOK
        if [ -n "$NOTIFY_WEBHOOK" ]; then
            echo -e "${GREEN}✓ Discord webhook configurado${NC}"
        fi
    fi
}

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
        # Escapar JSON para storage_config
        local escaped_config=$(echo "$storage_config" | jq -R -s '.')
        payload="{\"action\":\"set\",\"backupKeyHash\":\"$backup_key_hash\",\"storageType\":\"$storage_type\",\"storageConfig\":$escaped_config}"
    fi

    curl -s -X POST "$supabase_url" \
         -H "Authorization: Bearer $backup_secret" \
         -H "Content-Type: application/json" \
         -d "$payload"
}

# Função para gerar hash da senha mestra
generate_backup_key_hash() {
    local master_password="$1"
    echo -n "$master_password" | sha256sum | awk '{print $1}'
}

# Função para salvar metadados no Supabase
save_metadata_to_supabase() {
    local master_password="$1"
    local storage_type="$2"
    local config_bucket="$3"

    local backup_key_hash=$(generate_backup_key_hash "$master_password")

    # Configuração do storage
    local storage_config="{}"
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

# Função para buscar metadados do Supabase
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

# Salvar configuração criptografada
save_encrypted_config() {
    log_info "💾 Salvando configuração criptografada..."

    # Criar arquivo temporário com todas as configurações
    local temp_config="${SCRIPT_DIR}/temp_config.env"

    cat > "$temp_config" << EOF
# Configuração criptografada - $(date)
N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY"
N8N_POSTGRES_PASSWORD="$N8N_POSTGRES_PASSWORD"
ORACLE_NAMESPACE="$ORACLE_NAMESPACE"
ORACLE_COMPARTMENT_ID="$ORACLE_COMPARTMENT_ID"
ORACLE_CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
B2_ACCOUNT_ID="$B2_ACCOUNT_ID"
B2_APPLICATION_KEY="$B2_APPLICATION_KEY"
B2_CONFIG_BUCKET="$B2_CONFIG_BUCKET"
NOTIFY_WEBHOOK="$NOTIFY_WEBHOOK"
BACKUP_MASTER_PASSWORD="$BACKUP_MASTER_PASSWORD"
CONFIG_STORAGE_TYPE="$CONFIG_STORAGE_TYPE"
CONFIG_BUCKET="$CONFIG_BUCKET"
EOF

    # Criptografar arquivo com OpenSSL usando senha mestra
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$BACKUP_MASTER_PASSWORD" \
        -in "$temp_config" \
        -out "$ENCRYPTED_CONFIG_FILE"

    if [ $? -ne 0 ]; then
        log_error "Falha ao criptografar configuração"
        rm "$temp_config"
        return 1
    fi

    # Limpar arquivo temporário
    rm "$temp_config"

    # Upload para storages
    upload_encrypted_config

    echo -e "${GREEN}✓ Configuração salva e criptografada${NC}"
}

# Upload da configuração criptografada
upload_encrypted_config() {
    log_info "Enviando configuração para ${CONFIG_STORAGE_TYPE}..."

    # Validar se rclone está configurado
    if ! command -v rclone &> /dev/null; then
        log_error "rclone não instalado!"
        return 1
    fi

    # Upload baseado no storage escolhido
    if [ "$CONFIG_STORAGE_TYPE" = "oracle" ]; then
        if rclone ls "oracle:" > /dev/null 2>&1; then
            rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${CONFIG_BUCKET}/" --quiet
            if [ $? -eq 0 ]; then
                log_success "Configuração enviada para Oracle"
            else
                log_error "Falha ao enviar para Oracle"
            fi
        else
            log_error "Oracle rclone não configurado! Execute: rclone config"
        fi
    elif [ "$CONFIG_STORAGE_TYPE" = "b2" ]; then
        if rclone ls "b2:" > /dev/null 2>&1; then
            rclone copy "$ENCRYPTED_CONFIG_FILE" "b2:${CONFIG_BUCKET}/" --quiet
            if [ $? -eq 0 ]; then
                log_success "Configuração enviada para B2"
            else
                log_error "Falha ao enviar para B2"
            fi
        else
            log_error "B2 rclone não configurado! Execute: rclone config"
        fi
    fi
}

# Carregar configuração criptografada
load_encrypted_config() {
    log_info "📥 Carregando configuração do cloud..."

    # Pedir senha mestra
    echo ""
    echo -e "${BLUE}🔑 Digite sua senha mestra para carregar as configurações:${NC}"
    echo -n "> "
    read -s MASTER_PASSWORD
    echo ""

    if [ -z "$MASTER_PASSWORD" ]; then
        log_error "Senha mestra não pode ser vazia"
        return 1
    fi

    # Tentar carregar metadados do Supabase
    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        # Baixar configuração do storage identificado
        if [ "$CONFIG_STORAGE_TYPE" = "oracle" ]; then
            if rclone ls "oracle:${CONFIG_BUCKET}/config.enc" > /dev/null 2>&1; then
                rclone copy "oracle:${CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet
            fi
        elif [ "$CONFIG_STORAGE_TYPE" = "b2" ]; then
            if rclone ls "b2:${CONFIG_BUCKET}/config.enc" > /dev/null 2>&1; then
                rclone copy "b2:${CONFIG_BUCKET}/config.enc" "${SCRIPT_DIR}/" --quiet
            fi
        fi

        if [ -f "$ENCRYPTED_CONFIG_FILE" ]; then
            # Descriptografar
            local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
            openssl enc -d -aes-256-cbc -salt -pbkdf2 \
                -pass pass:"$MASTER_PASSWORD" \
                -in "$ENCRYPTED_CONFIG_FILE" \
                -out "$temp_decrypted" 2>/dev/null

            if [ $? -eq 0 ]; then
                # Carregar variáveis
                source "$temp_decrypted"
                BACKUP_MASTER_PASSWORD="$MASTER_PASSWORD"
                rm "$temp_decrypted"

                echo -e "${GREEN}✓ Configuração carregada com sucesso!${NC}"
                return 0
            else
                echo -e "${RED}❌ Senha mestra incorreta!${NC}"
                rm "$temp_decrypted" 2>/dev/null || true
                return 1
            fi
        else
            echo -e "${YELLOW}⚠ Arquivo de configuração não encontrado${NC}"
            return 1
        fi
    else
        return 1
    fi
}

# Aplicar configuração no config.env
apply_config_to_env() {
    log_info "📝 Aplicando configuração no config.env..."

    # Atualizar config.env com valores reais
    sed -i "s|N8N_ENCRYPTION_KEY=\".*\"|N8N_ENCRYPTION_KEY=\"$N8N_ENCRYPTION_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|N8N_POSTGRES_PASSWORD=\".*\"|N8N_POSTGRES_PASSWORD=\"$N8N_POSTGRES_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_NAMESPACE=\".*\"|ORACLE_NAMESPACE=\"$ORACLE_NAMESPACE\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_COMPARTMENT_ID=\".*\"|ORACLE_COMPARTMENT_ID=\"$ORACLE_COMPARTMENT_ID\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_ACCOUNT_ID=\".*\"|B2_ACCOUNT_ID=\"$B2_ACCOUNT_ID\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_APPLICATION_KEY=\".*\"|B2_APPLICATION_KEY=\"$B2_APPLICATION_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|BACKUP_MASTER_PASSWORD=\".*\"|BACKUP_MASTER_PASSWORD=\"$BACKUP_MASTER_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"

    if [ -n "$NOTIFY_WEBHOOK" ]; then
        sed -i "s|NOTIFY_WEBHOOK=\"\"|NOTIFY_WEBHOOK=\"$NOTIFY_WEBHOOK\"|g" "${SCRIPT_DIR}/config.env"
    fi

    echo -e "${GREEN}✓ Configuração aplicada com sucesso!${NC}"
}

# Setup interativo completo
interactive_setup() {
    echo ""
    echo -e "${BLUE}🚀 N8N Backup System - Configuração Interativa${NC}"
    echo -e "${BLUE}================================================${NC}"

    # Detectar credenciais automaticamente primeiro
    detect_credentials

    # Tentar carregar configuração existente do cloud
    if load_encrypted_config; then
        echo -e "${GREEN}✓ Configuração carregada do cloud!${NC}"
        apply_config_to_env
        
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    SISTEMA JÁ CONFIGURADO! 🎉         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "🎯 Sistema pronto para uso:"
        echo "   sudo ./n8n-backup.sh backup    # Fazer backup"
        echo "   sudo ./n8n-backup.sh status    # Ver status"
        echo ""
        return 0
    else
        # Se não conseguiu carregar, pedir credenciais
        echo -e "${YELLOW}⚠ Configuração não encontrada. Vamos configurar...${NC}"
        ask_credentials
    fi

    # Aplicar configuração
    apply_config_to_env

    # Salvar criptografado no cloud
    save_encrypted_config

    # Salvar metadados no Supabase
    save_metadata_to_supabase "$BACKUP_MASTER_PASSWORD" "$CONFIG_STORAGE_TYPE" "$CONFIG_BUCKET"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    CONFIGURAÇÃO CONCLUÍDA! 🎉         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "🎯 Próximos passos:"
    echo "   1. Configure o rclone: rclone config"
    echo "   2. Primeiro backup: sudo ./n8n-backup.sh backup"
    echo ""
}

# Função principal
main() {
    case "${1:-interactive}" in
        interactive)
            interactive_setup
            ;;
        detect)
            detect_credentials
            ;;
        save)
            save_encrypted_config
            ;;
        load)
            load_encrypted_config
            ;;
        *)
            echo "Uso: $0 {interactive|detect|save|load}"
            exit 1
            ;;
    esac
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi