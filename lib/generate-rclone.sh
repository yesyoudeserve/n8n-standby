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

    # DEBUG: Mostrar variáveis sendo usadas
    echo "DEBUG: ORACLE_NAMESPACE=$ORACLE_NAMESPACE"
    echo "DEBUG: ORACLE_REGION=$ORACLE_REGION"
    echo "DEBUG: ORACLE_ACCESS_KEY=${ORACLE_ACCESS_KEY:0:8}..."
    echo "DEBUG: B2_ACCOUNT_ID=${B2_ACCOUNT_ID:0:8}..."

    # Criar diretório rclone para usuário atual
    mkdir -p ~/.config/rclone

    # Gerar configuração base
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

EOF

    # B2 - Verificar se usa chaves separadas
    if [ "$B2_USE_SEPARATE_KEYS" = true ]; then
        log_info "Configurando B2 com chaves separadas por bucket..."
        
        # Remote para bucket de dados
        cat >> ~/.config/rclone/rclone.conf << EOF
[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_DATA_KEY}
hard_delete = false

[b2-config]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_CONFIG_KEY}
hard_delete = false
EOF
        
        log_warning "⚠️  B2 configurado com remotes separados:"
        log_warning "   - 'b2' para ${B2_BUCKET}"
        log_warning "   - 'b2-config' para ${B2_CONFIG_BUCKET}"
        
    else
        # Uma chave para tudo
        cat >> ~/.config/rclone/rclone.conf << EOF
[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
hard_delete = false
EOF
    fi

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
        
        # Testar remote separado se existir
        if [ "$B2_USE_SEPARATE_KEYS" = true ]; then
            if rclone lsd b2-config: > /dev/null 2>&1; then
                log_success "✓ B2-Config OK (usuário)"
            else
                log_warning "✗ B2-Config falhou (usuário) - verificar credenciais"
            fi
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
        
        # Testar remote separado se existir
        if [ "$B2_USE_SEPARATE_KEYS" = true ]; then
            if sudo rclone lsd b2-config: > /dev/null 2>&1; then
                log_success "✓ B2-Config OK (root)"
            else
                log_warning "✗ B2-Config falhou (root) - verificar credenciais"
            fi
        fi
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_rclone_config
fi
