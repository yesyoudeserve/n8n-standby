#!/bin/bash
# ============================================
# Gerar rclone.conf automaticamente
# Arquivo: /opt/n8n-backup/lib/generate-rclone.sh
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"

generate_rclone_config() {
    log_info "Gerando configuração rclone..."

    # Criar diretório rclone para usuário atual
    mkdir -p ~/.config/rclone

    # Gerar configuração
    cat > ~/.config/rclone/rclone.conf << EOF
# ============================================
# Configuração Rclone - Gerada automaticamente
# Data: $(date)
# ============================================

[oracle]
type = s3
provider = Other
endpoint = https://${ORACLE_NAMESPACE}.compat.objectstorage.${ORACLE_REGION}.oraclecloud.com
access_key_id = ${ORACLE_ACCESS_KEY}
secret_access_key = ${ORACLE_SECRET_KEY}
region = ${ORACLE_REGION}
acl = private

[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
hard_delete = false
EOF

    chmod 600 ~/.config/rclone/rclone.conf
    
    log_success "Configuração rclone gerada para usuário atual"
    
    # Copiar para root (necessário para sudo)
    log_info "Copiando configuração para root..."
    sudo mkdir -p /root/.config/rclone
    sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
    sudo chown root:root /root/.config/rclone/rclone.conf
    sudo chmod 600 /root/.config/rclone/rclone.conf
    
    log_success "Configuração rclone copiada para root"
    
    # Testar conexões (como usuário normal)
    echo ""
    log_info "Testando conexões (usuário)..."
    
    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone lsd oracle: > /dev/null 2>&1; then
            log_success "✓ Oracle OK (usuário)"
        else
            log_warning "✗ Oracle falhou (usuário) - verificar credenciais"
        fi
    fi
    
    if [ "$B2_ENABLED" = true ]; then
        if rclone lsd b2: > /dev/null 2>&1; then
            log_success "✓ B2 OK (usuário)"
        else
            log_warning "✗ B2 falhou (usuário) - verificar credenciais"
        fi
    fi
    
    # Testar conexões (como root)
    echo ""
    log_info "Testando conexões (root)..."
    
    if [ "$ORACLE_ENABLED" = true ]; then
        if sudo rclone lsd oracle: > /dev/null 2>&1; then
            log_success "✓ Oracle OK (root)"
        else
            log_warning "✗ Oracle falhou (root) - verificar credenciais"
        fi
    fi
    
    if [ "$B2_ENABLED" = true ]; then
        if sudo rclone lsd b2: > /dev/null 2>&1; then
            log_success "✓ B2 OK (root)"
        else
            log_warning "✗ B2 falhou (root) - verificar credenciais"
        fi
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_rclone_config
fi