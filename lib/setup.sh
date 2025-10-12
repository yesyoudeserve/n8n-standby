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
        echo -e "${GREEN}✓ B2 credentials configuradas${NC}"
    fi

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
    if [ "$ORACLE_ENABLED" = true ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "oracle:${ORACLE_BUCKET}/config/" --quiet 2>/dev/null || true
    fi

    if [ "$B2_ENABLED" = true ]; then
        rclone copy "$ENCRYPTED_CONFIG_FILE" "b2:${B2_BUCKET}/config/" --quiet 2>/dev/null || true
    fi
}

# Carregar configuração criptografada
load_encrypted_config() {
    log_info "📥 Carregando configuração do cloud..."

    local loaded=false

    # Tentar Oracle primeiro
    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone ls "oracle:${ORACLE_BUCKET}/config/config.enc" > /dev/null 2>&1; then
            rclone copy "oracle:${ORACLE_BUCKET}/config/config.enc" "${SCRIPT_DIR}/" --quiet
            loaded=true
        fi
    fi

    # Tentar B2 se não conseguiu do Oracle
    if [ "$loaded" = false ] && [ "$B2_ENABLED" = true ]; then
        if rclone ls "b2:${B2_BUCKET}/config/config.enc" > /dev/null 2>&1; then
            rclone copy "b2:${B2_BUCKET}/config/config.enc" "${SCRIPT_DIR}/" --quiet
            loaded=true
        fi
    fi

    if [ "$loaded" = true ] && [ -f "$ENCRYPTED_CONFIG_FILE" ]; then
        # Pedir senha mestra para descriptografar
        echo -e "${BLUE}🔑 Digite sua senha mestra para carregar as configurações:${NC}"
        read -s MASTER_PASSWORD
        echo ""

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
        echo -e "${YELLOW}⚠ Nenhuma configuração encontrada no cloud${NC}"
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
    else
        # Se não conseguiu carregar, pedir credenciais
        echo -e "${YELLOW}⚠ Configuração não encontrada. Vamos configurar...${NC}"
        ask_credentials
    fi

    # Aplicar configuração
    apply_config_to_env

    # Salvar criptografado no cloud para futuras instalações
    save_encrypted_config

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
