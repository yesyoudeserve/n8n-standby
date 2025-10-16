#!/bin/bash
# ============================================
# Backup Automático VM Standby N8N
# Sistema completo de backup para VM que virou produção
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

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED='\033[0;31m'}✗ Execute com sudo!${NC='\033[0m'}"
    echo "   sudo ./backup-production.sh"
    exit 1
fi

# Verificar modo especial
ENABLE_CRON=false
if [ "$1" = "--enable-cron" ]; then
    ENABLE_CRON=true
fi

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificar se é modo enable-cron
if [ "$ENABLE_CRON" = true ]; then
    echo -e "${BLUE}Configurando backup automático a cada 3h...${NC}"

    # Criar entrada no crontab para o usuário original
    ORIGINAL_USER=${SUDO_USER:-$USER}
    CRON_JOB="0 */3 * * * /opt/n8n-standby/backup-production.sh >> /opt/n8n-standby/logs/cron.log 2>&1"

    # Verificar se já existe
    if sudo -u $ORIGINAL_USER crontab -l 2>/dev/null | grep -q "n8n-standby"; then
        echo -e "${YELLOW}⚠ Cron job já existe${NC}"
    else
        (sudo -u $ORIGINAL_USER crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo -u $ORIGINAL_USER crontab -
        echo -e "${GREEN}✓ Backup automático configurado (a cada 3h)${NC}"
    fi

    echo -e "${BLUE}Para testar backup manual:${NC}"
    echo "   sudo ./backup-production.sh"
    exit 0
fi

# Variáveis de backup
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
BACKUP_DIR="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}"
BACKUP_ARCHIVE="${BACKUP_LOCAL_DIR}/${BACKUP_NAME}.tar.gz"

# Função principal de backup
main() {
    show_banner
    log_info "Iniciando backup N8N Standby - ${TIMESTAMP}"

    # 🚀 ALERTA: Início do backup
    send_discord_alert "🚀 **Backup Standby Iniciado**\n\nTimestamp: ${TIMESTAMP}\nServidor: $(hostname)" "info"

    # Verificar dependências
    check_dependencies

    # Verificar espaço em disco (requer pelo menos 500MB)
    check_disk_space 500 "${BACKUP_LOCAL_DIR}"

    # Testar conexão PostgreSQL
    test_postgres_connection || exit 1

    # Criar diretório temporário
    mkdir -p "${BACKUP_DIR}"

    # Inicializar segurança
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

# Backup das configurações EasyPanel (VERSÃO COMPLETA)
backup_easypanel_configs() {
    if [ "$BACKUP_EASYPANEL_CONFIGS" != true ]; then
        log_info "Backup de configs EasyPanel desabilitado"
        return 0
    fi

    log_info "Backup COMPLETO das configurações EasyPanel..."

    local config_dir="${BACKUP_DIR}/easypanel_configs"
    mkdir -p "${config_dir}"

    # Detectar se precisa usar sudo para Docker
    local docker_cmd="docker"
    if ! docker ps > /dev/null 2>&1; then
        if sudo docker ps > /dev/null 2>&1; then
            docker_cmd="sudo docker"
        fi
    fi

    # 1. Exportar TODOS os containers relacionados ao N8N
    log_info "Exportando containers N8N..."
    local n8n_containers=$($docker_cmd ps -a --filter "name=n8n" --format "{{.Names}}")

    for container in $n8n_containers; do
        log_info "  → ${container}"

        # Configuração completa do container
        $docker_cmd inspect "$container" > "${config_dir}/${container}_full_inspect.json"

        # Exportar variáveis de ambiente
        $docker_cmd inspect "$container" | jq '.[0].Config.Env' > "${config_dir}/${container}_env.json"

        # Exportar volumes
        $docker_cmd inspect "$container" | jq '.[0].Mounts' > "${config_dir}/${container}_volumes.json"

        # Exportar labels (importante no EasyPanel!)
        $docker_cmd inspect "$container" | jq '.[0].Config.Labels' > "${config_dir}/${container}_labels.json"
    done

    # 2. Exportar containers auxiliares (postgres, redis, pgadmin)
    log_info "Exportando containers auxiliares..."
    for service in postgres redis pgadmin; do
        local aux_containers=$($docker_cmd ps -a --filter "name=${service}" --format "{{.Names}}" 2>/dev/null)
        for container in $aux_containers; do
            if [[ "$container" == n8n* ]]; then
                log_info "  → ${container} (já exportado)"
            else
                log_info "  → ${container}"
                $docker_cmd inspect "$container" > "${config_dir}/${container}_full_inspect.json"
            fi
        done
    done

    # 3. Exportar networks
    log_info "Exportando Docker networks..."
    $docker_cmd network ls --format "{{.Name}}" | grep -v -E "^(bridge|host|none)$" > "${config_dir}/networks_list.txt" || true

    while read network; do
        if [ -n "$network" ]; then
            log_info "  → ${network}"
            $docker_cmd network inspect "$network" > "${config_dir}/network_${network}.json" 2>/dev/null || true
        fi
    done < "${config_dir}/networks_list.txt"

    # 4. Exportar volumes
    log_info "Exportando Docker volumes..."
    $docker_cmd volume ls --format "{{.Name}}" | grep -E "(n8n|postgres|redis)" > "${config_dir}/volumes_list.txt" || true

    while read volume; do
        if [ -n "$volume" ]; then
            log_info "  → ${volume}"
            $docker_cmd volume inspect "$volume" > "${config_dir}/volume_${volume}.json" 2>/dev/null || true
        fi
    done < "${config_dir}/volumes_list.txt"

    # 5. Localizar e copiar arquivos do EasyPanel (CRIPTOGRAFADO!)
    log_info "Procurando arquivos de configuração do EasyPanel..."

    local easypanel_paths=(
        "/etc/easypanel"
        "$HOME/.easypanel"
        "/opt/easypanel"
        "/var/lib/easypanel"
        "/usr/local/easypanel"
    )

    for path in "${easypanel_paths[@]}"; do
        if [ -d "$path" ]; then
            log_success "  ✓ Encontrado: $path"
            # Copiar e depois criptografar arquivos sensíveis
            local temp_dir="${config_dir}/easypanel_$(basename "$path")"
            sudo cp -r "$path" "$temp_dir" 2>/dev/null || \
                cp -r "$path" "$temp_dir" 2>/dev/null || \
                log_warning "  ⚠ Sem permissão para copiar: $path"

            # Criptografar arquivos sensíveis se existir
            if [ -d "$temp_dir" ]; then
                find "$temp_dir" -type f \( -name "*.env" -o -name "*.json" -o -name "*.yml" -o -name "*.yaml" \) | while read -r file; do
                    if [ -f "$file" ]; then
                        log_info "  🔐 Criptografando: $(basename "$file")"
                        # Usar função de criptografia do security.sh
                        source "${SCRIPT_DIR}/lib/security.sh"
                        load_encryption_key > /dev/null 2>&1
                        encrypt_file "$file" "${file}.enc" > /dev/null 2>&1
                        rm "$file" 2>/dev/null || true
                    fi
                done
            fi
        fi
    done

    # 6. Procurar docker-compose.yml
    log_info "Procurando docker-compose.yml..."

    local compose_paths=(
        "/opt/easypanel/projects/n8n/docker-compose.yml"
        "/var/lib/easypanel/projects/n8n/docker-compose.yml"
        "$HOME/easypanel/projects/n8n/docker-compose.yml"
        "/opt/n8n/docker-compose.yml"
    )

    for path in "${compose_paths[@]}"; do
        if [ -f "$path" ]; then
            log_success "  ✓ Encontrado: $path"
            cp "$path" "${config_dir}/docker-compose.yml"

            # Copiar diretório inteiro do projeto
            local project_dir=$(dirname "$path")
            if [ -d "$project_dir" ]; then
                sudo cp -r "$project_dir" "${config_dir}/project_directory" 2>/dev/null || \
                    cp -r "$project_dir" "${config_dir}/project_directory" 2>/dev/null || true
            fi
            break
        fi
    done

    # 7. Gerar script de recriação automática RECREATE.sh
    log_info "Gerando script de recriação automática..."

    cat > "${config_dir}/RECREATE.sh" << 'EOF'
#!/bin/bash
# ============================================
# Script de Recriação COMPLETA
# Gerado automaticamente pelo backup N8N
# ============================================

set -e

echo "╔════════════════════════════════════════╗"
echo "║   Recriação COMPLETA da Infraestrutura ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Verificar se EasyPanel está instalado
if ! command -v easypanel > /dev/null 2>&1 && ! docker ps | grep -q easypanel; then
    echo "❌ EasyPanel não encontrado. Instale primeiro:"
    echo "   curl -fsSL https://get.easypanel.io | bash"
    exit 1
fi

echo "[1/4] Recriando networks..."
EOF

    # Adicionar comandos para recriar networks
    if [ -f "${config_dir}/networks_list.txt" ]; then
        while read network; do
            if [ -n "$network" ]; then
                local driver=$(jq -r '.[0].Driver // .Driver // "bridge"' "${config_dir}/network_${network}.json" 2>/dev/null || echo "bridge")
                echo "docker network create --driver ${driver} ${network} 2>/dev/null || true" >> "${config_dir}/RECREATE.sh"
            fi
        done < "${config_dir}/networks_list.txt"
    fi

    cat >> "${config_dir}/RECREATE.sh" << 'EOF'

echo "[2/4] Recriando volumes..."
EOF

    # Adicionar comandos para volumes
    if [ -f "${config_dir}/volumes_list.txt" ]; then
        while read volume; do
            if [ -n "$volume" ]; then
                echo "docker volume create ${volume} 2>/dev/null || true" >> "${config_dir}/RECREATE.sh"
            fi
        done < "${config_dir}/volumes_list.txt"
    fi

    cat >> "${config_dir}/RECREATE.sh" << 'EOF'

echo "[3/4] Recriando containers..."
EOF

    # Gerar comandos docker run para cada container
    for container in $n8n_containers; do
        if [ -f "${config_dir}/${container}_full_inspect.json" ]; then
            local image=$($docker_cmd inspect "$container" 2>/dev/null | jq -r '.[0].Config.Image' 2>/dev/null || jq -r '.[0].Config.Image' "${config_dir}/${container}_full_inspect.json" 2>/dev/null)
            local network=$($docker_cmd inspect "$container" 2>/dev/null | jq -r '.[0].NetworkSettings.Networks | keys[0]' 2>/dev/null || jq -r '.[0].NetworkSettings.Networks | keys[0]' "${config_dir}/${container}_full_inspect.json" 2>/dev/null || echo "bridge")

            if [ -n "$image" ]; then
                echo "" >> "${config_dir}/RECREATE.sh"
                echo "# Container: ${container}" >> "${config_dir}/RECREATE.sh"
                echo "docker run -d \\" >> "${config_dir}/RECREATE.sh"
                echo "  --name ${container} \\" >> "${config_dir}/RECREATE.sh"
                echo "  --network ${network} \\" >> "${config_dir}/RECREATE.sh"

                # Adicionar variáveis de ambiente
                if [ -f "${config_dir}/${container}_env.json" ]; then
                    jq -r '.[]' "${config_dir}/${container}_env.json" 2>/dev/null | while read env; do
                        echo "  -e \"${env}\" \\" >> "${config_dir}/RECREATE.sh"
                    done
                fi

                # Adicionar volumes
                if [ -f "${config_dir}/${container}_volumes.json" ]; then
                    jq -r '.[] | "-v \(.Source):\(.Destination)"' "${config_dir}/${container}_volumes.json" 2>/dev/null | while read vol; do
                        echo "  ${vol} \\" >> "${config_dir}/RECREATE.sh"
                    done
                fi

                # Adicionar labels
                if [ -f "${config_dir}/${container}_labels.json" ]; then
                    jq -r 'to_entries[] | "--label \"\(.key)=\(.value)\""' "${config_dir}/${container}_labels.json" 2>/dev/null | while read label; do
                        echo "  ${label} \\" >> "${config_dir}/RECREATE.sh"
                    done
                fi

                echo "  ${image}" >> "${config_dir}/RECREATE.sh"
            fi
        fi
    done

    # Adicionar containers auxiliares
    for service in postgres redis pgadmin; do
        local aux_containers=$($docker_cmd ps -a --filter "name=${service}" --format "{{.Names}}" 2>/dev/null)
        for container in $aux_containers; do
            if [[ "$container" != n8n* ]] && [ -f "${config_dir}/${container}_full_inspect.json" ]; then
                local image=$(jq -r '.[0].Config.Image' "${config_dir}/${container}_full_inspect.json" 2>/dev/null)
                local network=$(jq -r '.[0].NetworkSettings.Networks | keys[0]' "${config_dir}/${container}_full_inspect.json" 2>/dev/null || echo "bridge")

                if [ -n "$image" ]; then
                    echo "" >> "${config_dir}/RECREATE.sh"
                    echo "# Container auxiliar: ${container}" >> "${config_dir}/RECREATE.sh"
                    echo "docker run -d \\" >> "${config_dir}/RECREATE.sh"
                    echo "  --name ${container} \\" >> "${config_dir}/RECREATE.sh"
                    echo "  --network ${network} \\" >> "${config_dir}/RECREATE.sh"
                    echo "  ${image}" >> "${config_dir}/RECREATE.sh"
                fi
            fi
        done
    done

    cat >> "${config_dir}/RECREATE.sh" << 'EOF'

echo "[4/4] Verificação final..."
docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "✅ Recriação concluída!"
echo ""
echo "📋 Próximos passos:"
echo "  1. Acesse o EasyPanel: http://localhost:3000"
echo "  2. Adicione os containers existentes ao EasyPanel (opcional)"
echo "  3. Execute o restore do banco N8N"
echo ""
EOF

    chmod +x "${config_dir}/RECREATE.sh"

    # 8. Criar README com instruções
    cat > "${config_dir}/README.md" << 'EOF'
# Backup Completo do Schema EasyPanel N8N

Este backup contém TODA a estrutura necessária para recriar o ambiente N8N completo.

## 📁 Conteúdo

- `*_full_inspect.json` - Configuração completa de cada container
- `network_*.json` - Configuração das Docker networks
- `volume_*.json` - Informações dos volumes
- `easypanel_*` - Arquivos de configuração do EasyPanel (criptografados)
- `docker-compose.yml` - Compose file original (se encontrado)
- `RECREATE.sh` - Script automático de recriação completa

## 🔄 Como Restaurar

### Opção 1: Disaster Recovery Completo
```bash
# Execute o script de recriação
chmod +x RECREATE.sh
./RECREATE.sh
```

### Opção 2: Via EasyPanel (Recomendado)
1. Instale o EasyPanel na nova VM
2. Use os arquivos `*_env.json` para recriar cada serviço
3. Configure os volumes conforme `*_volumes.json`

### Opção 3: Via Docker Compose
```bash
# Se docker-compose.yml existe neste backup:
docker-compose up -d
```

### Opção 4: Manual via Docker
Execute os comandos em `RECREATE.sh` individualmente.

## ⚠️ IMPORTANTE

Após recriar os containers, você ainda precisa:
1. Restaurar o banco PostgreSQL: `gunzip < n8n_dump.sql.gz | docker exec -i n8n_postgres psql -U postgres -d n8n`
2. Verificar se as credenciais do N8N estão corretas
3. Reiniciar os containers: `docker restart n8n-main n8n-worker n8n-webhook`

## 📝 Containers Incluídos

EOF

    echo "$n8n_containers" >> "${config_dir}/README.md"
    echo "" >> "${config_dir}/README.md"
    echo "**Data do backup:** ${TIMESTAMP}" >> "${config_dir}/README.md"

    log_success "Backup COMPLETO do schema EasyPanel finalizado"
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

# Banner
show_banner() {
    echo -e "${BLUE='\033[0;34m'}"
    echo "╔════════════════════════════════════════╗"
    echo "║   N8N Standby Production Backup        ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC='\033[0m'}"
}

# Executar
main "$@"
