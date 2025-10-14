#!/bin/bash
# ============================================
# Script Principal de Backup N8N
# Arquivo: /opt/n8n-backup/backup.sh
# Versão: 2.1 - Fix auto-sync rclone
# ============================================

set -euo pipefail

# Diretório base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/postgres.sh"
source "${SCRIPT_DIR}/lib/monitoring.sh"

# Variáveis
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
BACKUP_DIR="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}"
BACKUP_ARCHIVE="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}.tar.gz"

# Função principal
main() {
    show_banner
    log_info "Iniciando backup N8N - ${TIMESTAMP}"

    # 🚀 ALERTA: Início do backup
    send_discord_alert "🚀 **Backup Iniciado**\n\nTimestamp: ${TIMESTAMP}\nServidor: $(hostname)" "info"

    # Verificar dependências
    check_dependencies

    # Verificar espaço em disco (requer pelo menos 500MB)
    check_disk_space 500 "${BACKUP_LOCAL_DIR}"

    # Testar conexão PostgreSQL
    test_postgres_connection || exit 1

    # Criar diretório temporário
    mkdir -p "${BACKUP_DIR}"

    # Inicializar segurança (agora com auto-sync do rclone)
    init_security

    # 📊 ALERTA: Status - Preparação concluída
    send_discord_alert "📊 **Status: Preparação OK**\n\nDependências: ✅\nPostgreSQL: ✅\nEspaço: ✅" "info"

    # Executar backups
    backup_postgresql
    backup_easypanel_configs
    backup_encryption_key

    # Backup do config.env (com dados sigilosos)
    backup_config_file

    # Criptografar dados sensíveis se habilitado
    if [ "$ENCRYPT_SENSITIVE_DATA" = true ]; then
        encrypt_sensitive_data "${BACKUP_DIR}"
    fi

    # Criar arquivo compactado
    create_archive

    # Verificar integridade se habilitado
    if [ "$VERIFY_BACKUP_INTEGRITY" = true ]; then
        local file_hash=$(calculate_file_hash "${BACKUP_ARCHIVE}")
        echo "$file_hash" > "${BACKUP_ARCHIVE}.sha256"
        log_success "Hash de integridade: ${file_hash}"
    fi

    # 📤 ALERTA: Início dos uploads
    send_discord_alert "📤 **Iniciando Uploads**\n\nArquivo criado com sucesso.\nIniciando upload para storages..." "info"

    # Upload para storages remotos
    upload_to_oracle
    upload_to_b2

    # Salvar chave de criptografia no cloud
    save_encryption_key_to_cloud

    # Limpeza
    cleanup_old_backups

    # Alertas de sucesso
    local file_size=$(stat -c%s "${BACKUP_ARCHIVE}")
    if [ "$file_size" -ge 1073741824 ]; then
        local size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
    elif [ "$file_size" -ge 1048576 ]; then
        local size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
    elif [ "$file_size" -ge 1024 ]; then
        local size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
    else
        local size_display="${file_size}B"
    fi

    alert_backup_success "$(basename ${BACKUP_ARCHIVE})" "$size_display"

    log_success "Backup concluído com sucesso!"
    show_summary
}

# Verificar dependências
check_dependencies() {
    log_info "Verificando dependências..."
    
    local missing=()
    
    for cmd in pg_dump gzip tar rclone jq; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Dependências faltando: ${missing[*]}"
        log_info "Execute: sudo apt install -y postgresql-client gzip tar rclone jq"
        exit 1
    fi
    
    log_success "Todas as dependências OK"
}

# Backup do PostgreSQL
backup_postgresql() {
    log_info "Executando backup do PostgreSQL..."
    
    local dump_file="${BACKUP_DIR}/n8n_dump.sql.gz"
    
    # Usar backup seletivo (últimos 7 dias de executions)
    backup_postgres_selective "${dump_file}"
    
    if [ $? -eq 0 ]; then
        log_success "Backup PostgreSQL concluído"
        
        # Salvar estatísticas
        get_postgres_stats > "${BACKUP_DIR}/stats.txt"
    else
        log_error "Falha no backup PostgreSQL"
        exit 1
    fi
}

# Backup das configurações EasyPanel
backup_easypanel_configs() {
    if [ "$BACKUP_EASYPANEL_CONFIGS" != true ]; then
        log_info "Backup de configs EasyPanel desabilitado"
        return 0
    fi
    
    log_info "Backup das configurações EasyPanel..."
    
    local config_dir="${BACKUP_DIR}/easypanel_configs"
    mkdir -p "${config_dir}"
    
    # Detectar se precisa usar sudo para Docker
    local docker_cmd="docker"
    if ! docker ps > /dev/null 2>&1; then
        if sudo docker ps > /dev/null 2>&1; then
            docker_cmd="sudo docker"
        fi
    fi
    
    # Encontrar containers do n8n
    local n8n_containers=$($docker_cmd ps -a --filter "name=n8n" --format "{{.Names}}")
    
    for container in $n8n_containers; do
        log_info "Exportando configs do container: ${container}"
        
        # Exportar variáveis de ambiente
        $docker_cmd inspect "$container" | jq '.[0].Config.Env' > "${config_dir}/${container}_env.json"
        
        # Exportar volumes
        $docker_cmd inspect "$container" | jq '.[0].Mounts' > "${config_dir}/${container}_volumes.json"
        
        # Exportar labels (importante no EasyPanel!)
        $docker_cmd inspect "$container" | jq '.[0].Config.Labels' > "${config_dir}/${container}_labels.json"
    done
    
    # NOVO: Backup da estrutura completa do EasyPanel
    log_info "Procurando arquivos de configuração do EasyPanel..."
    
    # EasyPanel geralmente armazena configs em /etc/easypanel ou ~/.easypanel
    if [ -d "/etc/easypanel" ]; then
        sudo cp -r /etc/easypanel "${config_dir}/easypanel_etc" 2>/dev/null || true
    fi
    
    if [ -d "$HOME/.easypanel" ]; then
        cp -r "$HOME/.easypanel" "${config_dir}/easypanel_home" 2>/dev/null || true
    fi
    
    # Procurar docker-compose.yml do projeto n8n
    local possible_paths=(
        "/opt/easypanel/projects/n8n/docker-compose.yml"
        "/var/lib/easypanel/projects/n8n/docker-compose.yml"
        "$HOME/easypanel/projects/n8n/docker-compose.yml"
    )
    
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ]; then
            log_info "Encontrado docker-compose em: $path"
            cp "$path" "${config_dir}/docker-compose.yml"
            
            # Também copiar o diretório inteiro se existir
            local project_dir=$(dirname "$path")
            if [ -d "$project_dir" ]; then
                sudo cp -r "$project_dir" "${config_dir}/project_full" 2>/dev/null || true
            fi
            break
        fi
    done
    
    # Exportar network do Docker
    $docker_cmd network inspect $($docker_cmd inspect n8n-main 2>/dev/null | jq -r '.[0].NetworkSettings.Networks | keys[0]' 2>/dev/null) \
        > "${config_dir}/docker_network.json" 2>/dev/null || true
    
    # Criar um script de recriação automática
    cat > "${config_dir}/RECREATE_INSTRUCTIONS.md" << 'EOF'
# Como Recriar a Estrutura do EasyPanel

## Opção 1: Via EasyPanel (Recomendado)
1. Instale o EasyPanel na nova VM
2. Use os arquivos `*_env.json` para recriar cada serviço
3. Configure os volumes conforme `*_volumes.json`

## Opção 2: Via Docker Compose
1. Copie `docker-compose.yml` para a nova VM
2. Execute: `docker-compose up -d`

## Opção 3: Manual via Docker
Execute os comandos em `docker_recreate_commands.sh`
EOF
    
    # NOVO: Gerar comandos docker run para recriação manual
    cat > "${config_dir}/docker_recreate_commands.sh" << 'EOFSCRIPT'
#!/bin/bash
# Comandos para recriar os containers manualmente
# Gerado automaticamente pelo sistema de backup

EOFSCRIPT
    
    for container in $n8n_containers; do
        # Extrair comando docker run equivalente (aproximado)
        local image=$($docker_cmd inspect "$container" | jq -r '.[0].Config.Image')
        local network=$($docker_cmd inspect "$container" | jq -r '.[0].NetworkSettings.Networks | keys[0]')
        
        cat >> "${config_dir}/docker_recreate_commands.sh" << EOFCMD

# Container: ${container}
docker run -d \\
  --name ${container} \\
  --network ${network} \\
EOFCMD
        
        # Adicionar variáveis de ambiente
        $docker_cmd inspect "$container" | jq -r '.[0].Config.Env[]' | while read env; do
            echo "  -e \"${env}\" \\" >> "${config_dir}/docker_recreate_commands.sh"
        done
        
        # Adicionar volumes
        $docker_cmd inspect "$container" | jq -r '.[0].Mounts[] | "-v \(.Source):\(.Destination)"' | while read vol; do
            echo "  ${vol} \\" >> "${config_dir}/docker_recreate_commands.sh"
        done
        
        echo "  ${image}" >> "${config_dir}/docker_recreate_commands.sh"
        echo "" >> "${config_dir}/docker_recreate_commands.sh"
    done
    
    chmod +x "${config_dir}/docker_recreate_commands.sh"
    
    log_success "Configs EasyPanel exportadas (incluindo estrutura completa)"
}

# Backup da chave de criptografia (agora seguro)
backup_encryption_key() {
    log_info "Salvando encryption key de forma segura..."

    if [ -z "$N8N_ENCRYPTION_KEY" ] || [ "$N8N_ENCRYPTION_KEY" = "ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL" ]; then
        log_warning "N8N_ENCRYPTION_KEY não configurada! Credenciais não poderão ser restauradas!"
        return 1
    fi

    # Usar função segura do security.sh
    backup_n8n_encryption_key_securely "${BACKUP_DIR}"
}

# Backup do arquivo de configuração (com dados sigilosos)
backup_config_file() {
    log_info "Fazendo backup do config.env..."

    if [ -f "${SCRIPT_DIR}/config.env" ]; then
        cp "${SCRIPT_DIR}/config.env" "${BACKUP_DIR}/config.env"
        log_success "config.env incluído no backup (será criptografado)"
    else
        log_warning "config.env não encontrado"
    fi
}

# Criar arquivo compactado
create_archive() {
    log_info "Criando arquivo compactado..."
    
    show_progress "Compactando backup"
    
    tar -czf "${BACKUP_ARCHIVE}" -C "${BACKUP_LOCAL_DIR}" "${BACKUP_NAME}" 2>/dev/null | \
        pv -p -t -e -r -b > /dev/null 2>&1 || \
        tar -czf "${BACKUP_ARCHIVE}" -C "${BACKUP_LOCAL_DIR}" "${BACKUP_NAME}"
    
    clear_progress
    
    # Remover diretório temporário
    rm -rf "${BACKUP_DIR}"
    
    file_size=$(stat -c%s "${BACKUP_ARCHIVE}")
    if [ "$file_size" -ge 1073741824 ]; then
        size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
    elif [ "$file_size" -ge 1048576 ]; then
        size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
    elif [ "$file_size" -ge 1024 ]; then
        size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
    else
        size_display="${file_size}B"
    fi
    
    log_success "Arquivo criado: ${BACKUP_ARCHIVE} (${size_display})"
}

# Upload para Oracle Object Storage (S3)
upload_to_oracle() {
    if [ "$ORACLE_ENABLED" != true ]; then
        log_info "Upload para Oracle desabilitado"
        return 0
    fi

    log_info "Fazendo upload para Oracle Object Storage..."

    # Garantir rclone sincronizado antes do upload
    auto_sync_rclone

    # 📤 ALERTA: Status upload Oracle
    send_discord_alert "📤 **Upload Oracle: Iniciado**\n\nEnviando arquivo para Oracle Object Storage..." "info"

    show_progress "Upload para Oracle"

    if sudo rclone copy "${BACKUP_ARCHIVE}" "oracle:${ORACLE_BUCKET}/" --progress 2>&1 | \
        grep -oP '\d+%' | while read pct; do
            echo "$pct" | sed 's/%//'
        done; then
        
        clear_progress

        if sudo rclone lsf "oracle:${ORACLE_BUCKET}/" | grep -q "$(basename ${BACKUP_ARCHIVE})"; then
            log_success "Upload para Oracle concluído"
            send_discord_alert "✅ **Upload Oracle: Concluído**\n\nArquivo enviado com sucesso para Oracle Object Storage." "success"
        else
            log_error "Falha no upload para Oracle"
            send_discord_alert "❌ **Upload Oracle: Falhou**\n\nErro ao enviar arquivo para Oracle Object Storage." "error"
        fi
    else
        clear_progress
        log_error "Falha no upload para Oracle"
        send_discord_alert "❌ **Upload Oracle: Falhou**\n\nErro ao enviar arquivo para Oracle Object Storage." "error"
    fi
}

# Upload para Backblaze B2
upload_to_b2() {
    if [ "$B2_ENABLED" != true ]; then
        log_info "Upload para B2 desabilitado"
        return 0
    fi

    log_info "Fazendo upload para Backblaze B2..."

    # Garantir rclone sincronizado antes do upload
    auto_sync_rclone

    # 📤 ALERTA: Status upload B2
    send_discord_alert "📤 **Upload B2: Iniciado**\n\nEnviando arquivo para Backblaze B2..." "info"

    show_progress "Upload para B2"

    if sudo rclone copy "${BACKUP_ARCHIVE}" "b2:${B2_BUCKET}/" --progress 2>&1 | \
        grep -oP '\d+%' | while read pct; do
            echo "$pct" | sed 's/%//'
        done; then
        
        clear_progress

        if sudo rclone lsf "b2:${B2_BUCKET}/" | grep -q "$(basename ${BACKUP_ARCHIVE})"; then
            log_success "Upload para B2 concluído"
            send_discord_alert "✅ **Upload B2: Concluído**\n\nArquivo enviado com sucesso para Backblaze B2." "success"
        else
            log_error "Falha no upload para B2"
            send_discord_alert "❌ **Upload B2: Falhou**\n\nErro ao enviar arquivo para Backblaze B2." "error"
        fi
    else
        clear_progress
        log_error "Falha no upload para B2"
        send_discord_alert "❌ **Upload B2: Falhou**\n\nErro ao enviar arquivo para Backblaze B2." "error"
    fi
}

# Limpeza de backups antigos
cleanup_old_backups() {
    log_info "Limpando backups antigos..."
    
    # Limpeza local (manter apenas últimos 2 dias)
    find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f -mtime +${LOCAL_RETENTION_DAYS} -delete 2>/dev/null || true
    
    # Limpeza remota Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        cleanup_remote_backups "oracle" "${ORACLE_BUCKET}"
    fi
    
    # Limpeza remota B2
    if [ "$B2_ENABLED" = true ]; then
        cleanup_remote_backups "b2" "${B2_BUCKET}"
    fi
    
    log_success "Limpeza concluída"
}

# Limpeza de backups remotos
cleanup_remote_backups() {
    local remote=$1
    local bucket=$2
    
    log_info "Limpando backups remotos em ${remote}..."
    
    # Manter últimos 7 dias
    sudo rclone delete "${remote}:${bucket}/" \
        --min-age ${REMOTE_RETENTION_DAILY}d \
        --include "n8n_backup_*.tar.gz" 2>/dev/null || true
}

# Mostrar resumo
show_summary() {
    file_size=$(stat -c%s "${BACKUP_ARCHIVE}")
    if [ "$file_size" -ge 1073741824 ]; then
        backup_size="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
    elif [ "$file_size" -ge 1048576 ]; then
        backup_size="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
    elif [ "$file_size" -ge 1024 ]; then
        backup_size="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
    else
        backup_size="${file_size}B"
    fi
    
    local stats=$(cat "${BACKUP_DIR}/stats.txt" 2>/dev/null || echo "N/A")
    
    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║         RESUMO DO BACKUP               ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""
    echo "Arquivo: $(basename ${BACKUP_ARCHIVE})"
    echo "Tamanho: ${backup_size}"
    echo ""
    echo "Destinos:"
    [ "$ORACLE_ENABLED" = true ] && echo "  ✓ Oracle Object Storage"
    [ "$B2_ENABLED" = true ] && echo "  ✓ Backblaze B2 (offsite)"
    echo ""
}

# Tratamento de erros
trap 'log_error "Backup falhou na linha $LINENO"; exit 1' ERR

# Executar
main "$@"