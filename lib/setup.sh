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
        N8N_CONTAINER=$(docker ps --filter "name=n8n" --filter "name=n8n_main" --format "{{.Names}}" | grep -E "^n8n" | head -1 || echo "")
        if [ -n "$N8N_CONTAINER" ]; then
            DETECTED_N8N_KEY=$(docker exec "$N8N_CONTAINER" env 2>/dev/null | grep N8N_ENCRYPTION_KEY | cut -d'=' -f2 | tr -d '\r' || echo "")
            if [ -n "$DETECTED_N8N_KEY" ]; then
                N8N_ENCRYPTION_KEY="$DETECTED_N8N_KEY"
                echo -e "${GREEN}✓ N8N_ENCRYPTION_KEY detectada automaticamente do container: ${N8N_CONTAINER}${NC}"
            fi
        fi
    fi

    # Detectar PostgreSQL Password (EasyPanel usa nomes dinâmicos)
    if [ -z "$N8N_POSTGRES_PASSWORD" ] || [ "$N8N_POSTGRES_PASSWORD" = "ALTERAR_COM_SUA_SENHA_POSTGRES_REAL" ]; then
        # Procurar container PostgreSQL (pode ter sufixo dinâmico)
        POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | grep -E "^n8n.*postgres" | head -1 || echo "")
        if [ -n "$POSTGRES_CONTAINER" ]; then
            DETECTED_POSTGRES_PASS=$(docker exec "$POSTGRES_CONTAINER" env 2>/dev/null | grep POSTGRES_PASSWORD | cut -d'=' -f2 | tr -d '\r' || echo "")
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
    while [ -z "$BACKUP_MASTER_PASSWORD" ] || [ "$BACKUP_MASTER_PASSWORD" = "ALTERAR_COM_SUA_SENHA_MESTRA_REAL" ]; do
        echo -e "${YELLOW}Digite uma senha mestra forte (mínimo 12 caracteres):${NC}"
        echo -e "${YELLOW}Esta senha protege todas as suas credenciais!${NC}"
        read -s BACKUP_MASTER_PASSWORD
        echo ""

        if [ ${#BACKUP_MASTER_PASSWORD} -lt 12 ]; then
            echo -e "${RED}❌ Senha muito curta! Mínimo 12 caracteres.${NC}"
            BACKUP_MASTER_PASSWORD=""
        else
            echo -e "${GREEN}✓ Senha mestra aceita${NC}"
            break
        fi
    done

    # DEBUG: Mostrar que a senha foi capturada
    echo "DEBUG: Senha mestra tem ${#BACKUP_MASTER_PASSWORD} caracteres"
    echo "DEBUG: Conteúdo da senha (primeiros 10 chars): '${BACKUP_MASTER_PASSWORD:0:10}...'"

    # N8N Encryption Key
    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ "$N8N_ENCRYPTION_KEY" = "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ]; then
        echo ""
        echo -e "${YELLOW}N8N_ENCRYPTION_KEY (encontre no EasyPanel > Settings > Encryption):${NC}"
        read -s N8N_ENCRYPTION_KEY
        echo -e "${GREEN}✓ Encryption key configurada${NC}"
    fi

    # PostgreSQL Password
    if [ -z "$N8N_POSTGRES_PASSWORD" ] || [ "$N8N_POSTGRES_PASSWORD" = "ALTERAR_COM_SUA_SENHA_POSTGRES_REAL" ]; then
        echo ""
        echo -e "${YELLOW}N8N_POSTGRES_PASSWORD (senha do banco PostgreSQL):${NC}"
        read -s N8N_POSTGRES_PASSWORD
        echo -e "${GREEN}✓ PostgreSQL password configurada${NC}"
    fi

    # Oracle Credentials
    echo ""
    echo -e "${BLUE}Oracle Object Storage:${NC}"
    if [ -z "$ORACLE_NAMESPACE" ] || [ "$ORACLE_NAMESPACE" = "ALTERAR_COM_SEU_NAMESPACE_REAL" ]; then
        echo -e "${YELLOW}ORACLE_NAMESPACE:${NC}"
        read ORACLE_NAMESPACE
    fi

    if [ -z "$ORACLE_COMPARTMENT_ID" ] || [ "$ORACLE_COMPARTMENT_ID" = "ALTERAR_COM_SEU_COMPARTMENT_ID_REAL" ]; then
        echo -e "${YELLOW}ORACLE_COMPARTMENT_ID:${NC}"
        read ORACLE_COMPARTMENT_ID
    fi

    # Bucket de configuração Oracle (separado dos dados)
    if [ -z "$ORACLE_CONFIG_BUCKET" ] || [ "$ORACLE_CONFIG_BUCKET" = "ALTERAR_COM_SEU_BUCKET_CONFIG_REAL" ]; then
        echo -e "${YELLOW}ORACLE_CONFIG_BUCKET (bucket dedicado para configurações):${NC}"
        read ORACLE_CONFIG_BUCKET
    fi

    # B2 Credentials
    echo ""
    echo -e "${BLUE}Backblaze B2:${NC}"
    if [ -z "$B2_ACCOUNT_ID" ] || [ "$B2_ACCOUNT_ID" = "ALTERAR_COM_SEU_ACCOUNT_ID_REAL" ]; then
        echo -e "${YELLOW}B2_ACCOUNT_ID:${NC}"
        read B2_ACCOUNT_ID
    fi

    if [ -z "$B2_APPLICATION_KEY" ] || [ "$B2_APPLICATION_KEY" = "ALTERAR_COM_SUA_APP_KEY_REAL" ]; then
        echo -e "${YELLOW}B2_APPLICATION_KEY:${NC}"
        read -s B2_APPLICATION_KEY
        echo ""
    fi

    # Bucket de configuração B2 (separado dos dados)
    if [ -z "$B2_CONFIG_BUCKET" ] || [ "$B2_CONFIG_BUCKET" = "ALTERAR_COM_SEU_BUCKET_CONFIG_REAL" ]; then
        echo -e "${YELLOW}B2_CONFIG_BUCKET (bucket dedicado para configurações):${NC}"
        read B2_CONFIG_BUCKET
        echo -e "${GREEN}✓ B2 credentials configuradas${NC}"
    fi

    # Escolher storage para configurações
    echo ""
    echo -e "${BLUE}Escolha o storage para salvar as configurações:${NC}"
    echo "1) Oracle Object Storage"
    echo "2) Backblaze B2"
    echo -e "${YELLOW}Opção (1 ou 2):${NC}"
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
            echo -e "${RED}❌ Opção inválida. Usando Oracle por padrão.${NC}"
            CONFIG_STORAGE_TYPE="oracle"
            CONFIG_BUCKET="$ORACLE_CONFIG_BUCKET"
            ;;
    esac

    # Discord Webhook (opcional)
    echo ""
    echo -e "${BLUE}Discord Webhook (opcional - pressione ENTER para pular):${NC}"
    if [ -z "$NOTIFY_WEBHOOK" ] || [ "$NOTIFY_WEBHOOK" = "ALTERAR_COM_SEU_WEBHOOK_DISCORD_REAL" ]; then
        echo -e "${YELLOW}NOTIFY_WEBHOOK:${NC}"
        read NOTIFY_WEBHOOK
        if [ -n "$NOTIFY_WEBHOOK" ]; then
            echo -e "${GREEN}✓ Discord webhook configurado${NC}"
        fi
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
B2_ACCOUNT_ID="$B2_ACCOUNT_ID"
B2_APPLICATION_KEY="$B2_APPLICATION_KEY"
NOTIFY_WEBHOOK="$NOTIFY_WEBHOOK"
BACKUP_MASTER_PASSWORD="$BACKUP_MASTER_PASSWORD"
EOF

    # Criptografar arquivo
    encrypt_file "$temp_config" "$ENCRYPTED_CONFIG_FILE"

    # Limpar arquivo temporário
    rm "$temp_config"

    # Upload para storages
    upload_encrypted_config

    echo -e "${GREEN}✓ Configuração salva e criptografada no cloud${NC}"
}

# Upload da configuração criptografada
upload_encrypted_config() {
    # Usar bucket de configuração dedicado baseado na escolha do usuário
    if [ "$CONFIG_STORAGE_TYPE" = "oracle" ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${CONFIG_BUCKET}/" --quiet 2>/dev/null || true
    elif [ "$CONFIG_STORAGE_TYPE" = "b2" ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "b2:${CONFIG_BUCKET}/" --quiet 2>/dev/null || true
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
        log_error "Falha ao carregar metadados: $response"
        return 1
    fi
}

# Carregar configuração criptografada
load_encrypted_config() {
    log_info "📥 Carregando configuração do cloud..."

    # Primeiro tentar carregar metadados do Supabase
    echo -e "${BLUE}🔑 Digite sua senha mestra para carregar as configurações:${NC}"
    read -s MASTER_PASSWORD
    echo ""

    if load_metadata_from_supabase "$MASTER_PASSWORD"; then
        # Agora tentar baixar a configuração do storage identificado
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
            # Tentar descriptografar
            local temp_decrypted="${SCRIPT_DIR}/temp_decrypted.env"
            echo "$MASTER_PASSWORD" | openssl enc -d -aes-256-cbc -salt -pbkdf2 \
                -pass stdin \
                -in "$ENCRYPTED_CONFIG_FILE" \
                -out "$temp_decrypted" 2>/dev/null

            if [ $? -eq 0 ]; then
                # Carregar variáveis
                source "$temp_decrypted"

                # Atualizar BACKUP_MASTER_PASSWORD
                BACKUP_MASTER_PASSWORD="$MASTER_PASSWORD"

                # Limpar arquivo temporário
                rm "$temp_decrypted"

                echo -e "${GREEN}✓ Configuração carregada com sucesso!${NC}"
                return 0
            else
                echo -e "${RED}❌ Senha mestra incorreta!${NC}"
                rm "$temp_decrypted" 2>/dev/null || true
                return 1
            fi
        else
            echo -e "${YELLOW}⚠ Arquivo de configuração não encontrado no storage${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ Nenhuma configuração encontrada no Supabase${NC}"
        return 1
    fi
}

# Aplicar configuração no config.env
apply_config_to_env() {
    log_info "📝 Aplicando configuração no config.env..."

    # Atualizar config.env com valores reais
    sed -i "s|N8N_ENCRYPTION_KEY=\"ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL\"|N8N_ENCRYPTION_KEY=\"$N8N_ENCRYPTION_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|N8N_POSTGRES_PASSWORD=\"ALTERAR_COM_SUA_SENHA_POSTGRES_REAL\"|N8N_POSTGRES_PASSWORD=\"$N8N_POSTGRES_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_NAMESPACE=\"ALTERAR_COM_SEU_NAMESPACE_REAL\"|ORACLE_NAMESPACE=\"$ORACLE_NAMESPACE\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|ORACLE_COMPARTMENT_ID=\"ALTERAR_COM_SEU_COMPARTMENT_ID_REAL\"|ORACLE_COMPARTMENT_ID=\"$ORACLE_COMPARTMENT_ID\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_ACCOUNT_ID=\"ALTERAR_COM_SEU_ACCOUNT_ID_REAL\"|B2_ACCOUNT_ID=\"$B2_ACCOUNT_ID\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|B2_APPLICATION_KEY=\"ALTERAR_COM_SUA_APP_KEY_REAL\"|B2_APPLICATION_KEY=\"$B2_APPLICATION_KEY\"|g" "${SCRIPT_DIR}/config.env"
    sed -i "s|BACKUP_MASTER_PASSWORD=\"ALTERAR_COM_SUA_SENHA_MESTRA_REAL\"|BACKUP_MASTER_PASSWORD=\"$BACKUP_MASTER_PASSWORD\"|g" "${SCRIPT_DIR}/config.env"

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
        echo -e "${GREEN}✅ Sistema já configurado. Pulando configuração inicial.${NC}"
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║    SISTEMA JÁ CONFIGURADO! 🎉         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo "🎯 Sistema pronto para uso:"
        echo "   ./n8n-backup.sh backup    # Fazer backup"
        echo "   ./n8n-backup.sh status    # Ver status"
        echo "   ./n8n-backup.sh restore   # Restaurar dados"
        echo ""
        return 0
    else
        # Se não conseguiu carregar, pedir credenciais
        echo -e "${YELLOW}⚠ Configuração não encontrada. Vamos configurar...${NC}"
        ask_credentials
    fi

    # Aplicar configuração
    apply_config_to_env

    # Salvar criptografado no cloud para futuras instalações
    save_encrypted_config

    # Salvar metadados no Supabase
    save_metadata_to_supabase "$BACKUP_MASTER_PASSWORD" "$CONFIG_STORAGE_TYPE" "$CONFIG_BUCKET"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    CONFIGURAÇÃO CONCLUÍDA! 🎉         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "🎯 Agora você pode executar:"
    echo "   ./n8n-backup.sh backup    # Primeiro backup"
    echo "   ./n8n-backup.sh status    # Ver status"
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
