#!/bin/bash
# =============================================
# Setup Interativo de Credenciais
# Menu para configurar credenciais da VM Standby
# Baseado no sistema principal com Supabase
# =============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh"

# Carregar funções do sistema principal
if [ -f "${SCRIPT_DIR}/../lib/setup.sh" ]; then
    source "${SCRIPT_DIR}/../lib/setup.sh"
    source "${SCRIPT_DIR}/../lib/security.sh"
fi

# Arquivo de configuração
CONFIG_FILE="${SCRIPT_DIR}/config.env"
TEMPLATE_FILE="${SCRIPT_DIR}/config.env.template"

# Cores para dialog
DIALOG_CANCEL=1
DIALOG_ESC=255

# Função para mostrar menu principal
show_main_menu() {
    local choice
    while true; do
        choice=$(dialog --clear --backtitle "N8N Standby VM - Configuração de Credenciais" \
            --title "Menu Principal" \
            --menu "Escolha uma opção:" 15 60 7 \
            1 "Carregar do Supabase (Recomendado)" \
            2 "Configurar Oracle Cloud" \
            3 "Configurar Backblaze B2" \
            4 "Configurar PostgreSQL" \
            5 "Configurar Segurança" \
            6 "Testar Configurações" \
            7 "Salvar e Sair" \
            2>&1 >/dev/tty)

        case $? in
            $DIALOG_CANCEL|$DIALOG_ESC)
                return 1
                ;;
        esac

        case $choice in
            1) load_from_supabase ;;
            2) configure_oracle ;;
            3) configure_b2 ;;
            4) configure_postgres ;;
            5) configure_security ;;
            6) test_configuration ;;
            7) save_and_exit ;;
        esac
    done
}

# Configurar Oracle Cloud
configure_oracle() {
    local enabled oracle_namespace oracle_region oracle_access_key oracle_secret_key oracle_bucket

    # Carregar valores atuais se existirem
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    enabled=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
        --title "Habilitar Oracle Cloud" \
        --menu "Usar Oracle Cloud para backup?" 10 50 2 \
        1 "Sim" \
        2 "Não" \
        2>&1 >/dev/tty)

    case $enabled in
        1) ORACLE_ENABLED=true ;;
        2) ORACLE_ENABLED=false ;;
        *) return ;;
    esac

    if [ "$ORACLE_ENABLED" = true ]; then
        oracle_namespace=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
            --title "Oracle Namespace" \
            --inputbox "Digite seu Oracle Namespace:" 8 50 "$ORACLE_NAMESPACE" \
            2>&1 >/dev/tty)

        oracle_region=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
            --title "Oracle Region" \
            --inputbox "Digite sua Oracle Region (ex: eu-madrid-1):" 8 50 "$ORACLE_REGION" \
            2>&1 >/dev/tty)

        oracle_access_key=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
            --title "Oracle Access Key" \
            --passwordbox "Digite sua Oracle Access Key:" 8 50 "$ORACLE_ACCESS_KEY" \
            2>&1 >/dev/tty)

        oracle_secret_key=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
            --title "Oracle Secret Key" \
            --passwordbox "Digite sua Oracle Secret Key:" 8 50 \
            2>&1 >/dev/tty)

        oracle_bucket=$(dialog --clear --backtitle "Oracle Cloud Configuration" \
            --title "Oracle Bucket" \
            --inputbox "Digite o nome do bucket Oracle:" 8 50 "$ORACLE_BUCKET" \
            2>&1 >/dev/tty)

        # Salvar variáveis
        ORACLE_NAMESPACE="$oracle_namespace"
        ORACLE_REGION="$oracle_region"
        ORACLE_ACCESS_KEY="$oracle_access_key"
        ORACLE_SECRET_KEY="$oracle_secret_key"
        ORACLE_BUCKET="$oracle_bucket"
    fi
}

# Configurar Backblaze B2
configure_b2() {
    local enabled b2_account_id b2_application_key b2_bucket

    # Carregar valores atuais
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    enabled=$(dialog --clear --backtitle "Backblaze B2 Configuration" \
        --title "Habilitar Backblaze B2" \
        --menu "Usar Backblaze B2 para backup?" 10 50 2 \
        1 "Sim" \
        2 "Não" \
        2>&1 >/dev/tty)

    case $enabled in
        1) B2_ENABLED=true ;;
        2) B2_ENABLED=false ;;
        *) return ;;
    esac

    if [ "$B2_ENABLED" = true ]; then
        b2_account_id=$(dialog --clear --backtitle "Backblaze B2 Configuration" \
            --title "B2 Account ID" \
            --inputbox "Digite seu B2 Account ID:" 8 50 "$B2_ACCOUNT_ID" \
            2>&1 >/dev/tty)

        b2_application_key=$(dialog --clear --backtitle "Backblaze B2 Configuration" \
            --title "B2 Application Key" \
            --passwordbox "Digite sua B2 Application Key:" 8 50 "$B2_APPLICATION_KEY" \
            2>&1 >/dev/tty)

        b2_bucket=$(dialog --clear --backtitle "Backblaze B2 Configuration" \
            --title "B2 Bucket" \
            --inputbox "Digite o nome do bucket B2:" 8 50 "$B2_BUCKET" \
            2>&1 >/dev/tty)

        # Salvar variáveis
        B2_ACCOUNT_ID="$b2_account_id"
        B2_APPLICATION_KEY="$b2_application_key"
        B2_BUCKET="$b2_bucket"
    fi
}

# Configurar PostgreSQL
configure_postgres() {
    local postgres_host postgres_port postgres_user postgres_password postgres_db

    # Carregar valores atuais
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    postgres_host=$(dialog --clear --backtitle "PostgreSQL Configuration" \
        --title "PostgreSQL Host" \
        --inputbox "Host do PostgreSQL (localhost):" 8 50 "${POSTGRES_HOST:-localhost}" \
        2>&1 >/dev/tty)

    postgres_port=$(dialog --clear --backtitle "PostgreSQL Configuration" \
        --title "PostgreSQL Port" \
        --inputbox "Porta do PostgreSQL (5432):" 8 50 "${POSTGRES_PORT:-5432}" \
        2>&1 >/dev/tty)

    postgres_user=$(dialog --clear --backtitle "PostgreSQL Configuration" \
        --title "PostgreSQL User" \
        --inputbox "Usuário do PostgreSQL (n8n):" 8 50 "${POSTGRES_USER:-n8n}" \
        2>&1 >/dev/tty)

    postgres_password=$(dialog --clear --backtitle "PostgreSQL Configuration" \
        --title "PostgreSQL Password" \
        --passwordbox "Senha do PostgreSQL:" 8 50 "$POSTGRES_PASSWORD" \
        2>&1 >/dev/tty)

    postgres_db=$(dialog --clear --backtitle "PostgreSQL Configuration" \
        --title "PostgreSQL Database" \
        --inputbox "Nome do banco (n8n):" 8 50 "${POSTGRES_DB:-n8n}" \
        2>&1 >/dev/tty)

    # Salvar variáveis
    POSTGRES_HOST="$postgres_host"
    POSTGRES_PORT="$postgres_port"
    POSTGRES_USER="$postgres_user"
    POSTGRES_PASSWORD="$postgres_password"
    POSTGRES_DB="$postgres_db"
}

# Configurar Segurança
configure_security() {
    local master_password

    # Carregar valores atuais
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    dialog --clear --backtitle "Configuração de Segurança" \
        --title "Senha Mestre" \
        --msgbox "A senha mestre é usada para criptografar/descriptografar backups. Guarde-a em local seguro!" 8 60

    master_password=$(dialog --clear --backtitle "Configuração de Segurança" \
        --title "Senha Mestre" \
        --passwordbox "Digite a senha mestre (mínimo 12 caracteres):" 8 50 "$BACKUP_MASTER_PASSWORD" \
        2>&1 >/dev/tty)

    # Confirmar senha
    local confirm_password=$(dialog --clear --backtitle "Configuração de Segurança" \
        --title "Confirmar Senha Mestre" \
        --passwordbox "Confirme a senha mestre:" 8 50 \
        2>&1 >/dev/tty)

    if [ "$master_password" != "$confirm_password" ]; then
        dialog --clear --backtitle "Erro" \
            --title "Senhas não conferem" \
            --msgbox "As senhas digitadas não são iguais. Tente novamente." 6 50
        return
    fi

    if [ ${#master_password} -lt 12 ]; then
        dialog --clear --backtitle "Erro" \
            --title "Senha muito fraca" \
            --msgbox "A senha deve ter pelo menos 12 caracteres." 6 50
        return
    fi

    BACKUP_MASTER_PASSWORD="$master_password"
}

# Testar configurações
test_configuration() {
    local test_output="/tmp/standby_test_$$.log"

    dialog --clear --backtitle "Teste de Configuração" \
        --title "Executando testes..." \
        --infobox "Testando configurações. Aguarde..." 5 40

    {
        echo "=== TESTE DE CONFIGURAÇÃO ==="
        echo "Data: $(date)"
        echo ""

        # Testar rclone se configurado
        if [ "$ORACLE_ENABLED" = true ] || [ "$B2_ENABLED" = true ]; then
            echo "Testando rclone..."
            source "${SCRIPT_DIR}/lib/generate-rclone.sh"
            generate_rclone_config > /dev/null 2>&1
            echo "✓ Configuração rclone gerada"
        fi

        # Testar PostgreSQL se configurado
        if [ -n "$POSTGRES_PASSWORD" ]; then
            echo "Testando PostgreSQL..."
            source "${SCRIPT_DIR}/lib/postgres.sh"
            if check_postgres_connection > /dev/null 2>&1; then
                echo "✓ Conexão PostgreSQL OK"
            else
                echo "✗ Conexão PostgreSQL falhou"
            fi
        fi

        echo ""
        echo "=== FIM DO TESTE ==="

    } > "$test_output" 2>&1

    dialog --clear --backtitle "Resultado do Teste" \
        --title "Resultado dos Testes" \
        --textbox "$test_output" 20 70

    rm -f "$test_output"
}

# Carregar do Supabase
load_from_supabase() {
    local master_password

    dialog --clear --backtitle "Carregar do Supabase" \
        --title "Carregar Configurações" \
        --msgbox "Esta opção irá carregar as configurações criptografadas do Supabase.\n\nVocê precisa da senha mestre usada na VM principal." 10 60

    master_password=$(dialog --clear --backtitle "Carregar do Supabase" \
        --title "Senha Mestre" \
        --passwordbox "Digite a senha mestre da VM principal:" 8 50 \
        2>&1 >/dev/tty)

    if [ -z "$master_password" ]; then
        dialog --clear --backtitle "Erro" \
            --title "Senha vazia" \
            --msgbox "Senha não pode ser vazia." 6 40
        return
    fi

    # Tentar carregar do Supabase
    dialog --clear --backtitle "Carregando..." \
        --title "Carregando configurações..." \
        --infobox "Buscando metadados no Supabase..." 5 40

    if load_metadata_from_supabase "$master_password"; then
        BACKUP_MASTER_PASSWORD="$master_password"

        # Gerar rclone com as credenciais carregadas
        source "${SCRIPT_DIR}/../lib/generate-rclone.sh"
        generate_rclone_config > /dev/null 2>&1

        dialog --clear --backtitle "Sucesso!" \
            --title "Configurações carregadas" \
            --msgbox "✅ Configurações carregadas com sucesso do Supabase!\n\nAgora você pode testar as configurações." 8 50
    else
        dialog --clear --backtitle "Erro" \
            --title "Falha ao carregar" \
            --msgbox "❌ Não foi possível carregar as configurações.\n\nVerifique:\n- Senha mestre correta\n- Conexão com internet\n- Configurações salvas na VM principal" 10 50
    fi
}

# Salvar e sair
save_and_exit() {
    # Salvar metadados no Supabase se temos senha mestre
    if [ -n "$BACKUP_MASTER_PASSWORD" ]; then
        dialog --clear --backtitle "Salvando..." \
            --title "Salvando configurações..." \
            --infobox "Salvando metadados criptografados no Supabase..." 5 50

        save_metadata_to_supabase
    fi

    # Criar arquivo de configuração
    cat > "$CONFIG_FILE" << EOF
# ============================================
# Configuração N8N Standby VM
# Gerado automaticamente em $(date)
# ============================================

# Oracle Cloud
ORACLE_ENABLED=${ORACLE_ENABLED:-false}
ORACLE_NAMESPACE="${ORACLE_NAMESPACE:-ALTERAR_COM_SEU_NAMESPACE_REAL}"
ORACLE_REGION="${ORACLE_REGION:-eu-madrid-1}"
ORACLE_ACCESS_KEY="${ORACLE_ACCESS_KEY:-ALTERAR_COM_SEU_ACCESS_KEY_REAL}"
ORACLE_SECRET_KEY="${ORACLE_SECRET_KEY:-ALTERAR_COM_SEU_SECRET_KEY_REAL}"
ORACLE_BUCKET="${ORACLE_BUCKET:-n8n-backups}"

# Backblaze B2
B2_ENABLED=${B2_ENABLED:-false}
B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-ALTERAR_COM_SEU_ACCOUNT_ID_REAL}"
B2_APPLICATION_KEY="${B2_APPLICATION_KEY:-ALTERAR_COM_SUA_APP_KEY_REAL}"
B2_BUCKET="${B2_BUCKET:-n8n-backups}"

# PostgreSQL
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"

# Segurança
BACKUP_MASTER_PASSWORD="${BACKUP_MASTER_PASSWORD:-}"

# Configurações avançadas
UPLOAD_RETRIES=3
UPLOAD_TIMEOUT=300
EOF

    chmod 600 "$CONFIG_FILE"

    dialog --clear --backtitle "Configuração Salva" \
        --title "Sucesso!" \
        --msgbox "Configuração salva em: $CONFIG_FILE\n\nAgora você pode executar:\n  ./sync-standby.sh --test" 10 50

    exit 0
}

# Verificar dependências
check_dependencies() {
    if ! command -v dialog &> /dev/null; then
        log_error "Dialog não encontrado. Instale com: sudo apt install dialog"
        exit 1
    fi
}

# Função principal
main() {
    check_dependencies

    show_banner

    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "Arquivo template não encontrado: $TEMPLATE_FILE"
        exit 1
    fi

    log_info "Iniciando configuração interativa..."
    log_info "Arquivo será salvo em: $CONFIG_FILE"

    if show_main_menu; then
        log_info "Configuração cancelada pelo usuário"
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
