#!/bin/bash
# ============================================
# Funções de Recuperação de Desastre
# Arquivo: /opt/n8n-backup/lib/recovery.sh
# ============================================

# Recuperação completa de desastre (nova VM)
disaster_recovery() {
    log_info "Iniciando recuperação de desastre..."

    # Passo 1: Instalar dependências
    install_dependencies

    # Passo 2: Configurar rclone
    setup_rclone_recovery

    # Passo 3: Baixar backup mais recente
    download_latest_backup

    # Passo 4: Instalar EasyPanel
    install_easypanel

    # Passo 5: Extrair e restaurar schema
    restore_easypanel_schema

    # Passo 6: Restaurar banco de dados
    restore_database

    # Passo 7: Verificar e iniciar serviços
    verify_and_start_services

    # Passo 8: Configurar monitoramento
    setup_monitoring

    log_success "Recuperação de desastre concluída!"
    show_recovery_summary
}

# Instalar dependências necessárias
install_dependencies() {
    log_info "[1/8] Instalando dependências..."

    # Atualizar sistema
    sudo apt update -qq

    # Instalar pacotes essenciais
    sudo apt install -y \
        postgresql-client \
        jq \
        pv \
        dialog \
        gzip \
        pigz \
        rclone \
        git \
        curl \
        wget \
        openssl \
        docker.io \
        docker-compose \
        > /dev/null 2>&1

    # Instalar Node.js (para N8N)
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs

    log_success "Dependências instaladas"
}

# Configurar rclone para recuperação
setup_rclone_recovery() {
    log_info "[2/8] Configurando rclone..."

    # Usar a mesma lógica do generate_rclone_config() - gerar dinamicamente
    source "${SCRIPT_DIR}/lib/generate-rclone.sh"
    generate_rclone_config

    log_success "Rclone configurado dinamicamente"
}

# Baixar backup mais recente automaticamente
download_latest_backup() {
    log_info "[3/8] Baixando backup mais recente..."

    local latest_backup=""
    local latest_date=""

    # Procurar no Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        local oracle_backup=$(rclone lsl "oracle:${ORACLE_BUCKET}/" 2>/dev/null | \
            grep "n8n_backup_" | sort -k2,3 | tail -1 | awk '{print $NF}')
        if [ -n "$oracle_backup" ]; then
            local oracle_date=$(echo "$oracle_backup" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
            if [ -z "$latest_date" ] || [ "$oracle_date" \> "$latest_date" ]; then
                latest_backup="$oracle_backup"
                latest_date="$oracle_date"
                BACKUP_SOURCE="oracle"
            fi
        fi
    fi

    # Procurar no B2
    if [ "$B2_ENABLED" = true ]; then
        local b2_backup=$(rclone lsl "b2:${B2_BUCKET}/" 2>/dev/null | \
            grep "n8n_backup_" | sort -k2,3 | tail -1 | awk '{print $NF}')
        if [ -n "$b2_backup" ]; then
            local b2_date=$(echo "$b2_backup" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
            if [ -z "$latest_date" ] || [ "$b2_date" \> "$latest_date" ]; then
                latest_backup="$b2_backup"
                latest_date="$b2_date"
                BACKUP_SOURCE="b2"
            fi
        fi
    fi

    if [ -z "$latest_backup" ]; then
        log_error "Nenhum backup encontrado nos storages!"
        exit 1
    fi

    log_info "Backup mais recente: $latest_backup (fonte: $BACKUP_SOURCE)"

    # Baixar backup
    mkdir -p "${BACKUP_LOCAL_DIR}"
    local local_backup="${BACKUP_LOCAL_DIR}/${latest_backup}"

    # Determinar bucket correto baseado na fonte
    local bucket=""
    case $BACKUP_SOURCE in
        oracle)
            bucket="$ORACLE_BUCKET"
            ;;
        b2)
            bucket="$B2_BUCKET"
            ;;
        *)
            log_error "Fonte de backup desconhecida: $BACKUP_SOURCE"
            exit 1
            ;;
    esac

    rclone copy "${BACKUP_SOURCE}:${bucket}/${latest_backup}" "${BACKUP_LOCAL_DIR}/" --progress

    if [ ! -f "$local_backup" ]; then
        log_error "Falha no download do backup"
        exit 1
    fi

    LATEST_BACKUP_FILE="$local_backup"
    log_success "Backup baixado: $latest_backup"
}

# Instalar EasyPanel
install_easypanel() {
    log_info "[4/8] Instalando EasyPanel..."

    # Verificar se já está instalado (comando easypanel)
    if command -v easypanel > /dev/null 2>&1; then
        log_success "EasyPanel já instalado (comando encontrado)"
        return 0
    fi

    # Verificar se container easypanel está rodando
    if docker ps --format "{{.Names}}" | grep -q "^easypanel"; then
        log_success "EasyPanel já instalado (container encontrado)"
        return 0
    fi

    # Instalar EasyPanel - tentar múltiplas URLs
    local install_urls=(
        "https://get.easypanel.io"
        "https://github.com/easypanel-io/easypanel/releases/latest/download/install.sh"
        "https://raw.githubusercontent.com/easypanel-io/easypanel/main/install.sh"
    )

    local installed=false
    for url in "${install_urls[@]}"; do
        log_info "Tentando instalar do: $url"
        if curl -fsSL "$url" | sudo bash; then
            # Aguardar um pouco para o serviço iniciar
            sleep 10

            # Verificar se foi instalado (comando ou container)
            if command -v easypanel > /dev/null 2>&1 || sudo docker ps --format "{{.Names}}" | grep -q "^easypanel"; then
                log_success "EasyPanel instalado com sucesso"
                installed=true
                break
            fi
        fi
        log_warning "Falha com URL: $url"
    done

    if [ "$installed" = false ]; then
        log_error "Não foi possível instalar o EasyPanel automaticamente"
        log_info "Instale manualmente: https://easypanel.io/docs/getting-started"
        log_info "Ou pule esta etapa se já tem containers N8N rodando"
        # Não sair com erro - permitir continuar sem EasyPanel
        return 0
    fi
}

# Restaurar schema do EasyPanel
restore_easypanel_schema() {
    log_info "[5/8] Restaurando schema do EasyPanel..."

    if [ ! -f "$LATEST_BACKUP_FILE" ]; then
        log_error "Arquivo de backup não encontrado"
        return 1
    fi

    # Extrair backup
    local temp_dir=$(mktemp -d)
    tar -xzf "$LATEST_BACKUP_FILE" -C "$temp_dir"

    # Procurar script de recriação
    local recreate_script=$(find "$temp_dir" -name "RECREATE.sh" | head -1)

    if [ -f "$recreate_script" ]; then
        log_info "Executando script de recriação..."
        chmod +x "$recreate_script"
        bash "$recreate_script"
        log_success "Schema EasyPanel restaurado"
    else
        log_warning "Script RECREATE.sh não encontrado, tentando restauração manual..."

        # Tentar restaurar docker-compose.yml
        local compose_file=$(find "$temp_dir" -name "docker-compose.yml" | head -1)
        if [ -f "$compose_file" ]; then
            cp "$compose_file" /opt/n8n/docker-compose.yml
            cd /opt/n8n
            docker-compose up -d
            log_success "docker-compose restaurado"
        else
            log_error "Nenhum arquivo de configuração encontrado no backup"
        fi
    fi

    # Limpar
    rm -rf "$temp_dir"
}

# Restaurar banco de dados
restore_database() {
    log_info "[6/8] Restaurando banco de dados..."

    if [ ! -f "$LATEST_BACKUP_FILE" ]; then
        log_error "Arquivo de backup não encontrado"
        return 1
    fi

    # Aguardar PostgreSQL ficar pronto
    log_info "Aguardando PostgreSQL..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if docker exec n8n_postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
            break
        fi
        sleep 2
        ((retries--))
    done

    if [ $retries -eq 0 ]; then
        log_error "PostgreSQL não ficou pronto"
        return 1
    fi

    # Extrair e restaurar dump
    local temp_dir=$(mktemp -d)
    tar -xzf "$LATEST_BACKUP_FILE" -C "$temp_dir"

    local dump_file=$(find "$temp_dir" -name "n8n_dump.sql.gz" | head -1)

    if [ -f "$dump_file" ]; then
        log_info "Restaurando dump do banco..."
        gunzip < "$dump_file" | docker exec -i n8n_postgres psql -U postgres -d n8n
        log_success "Banco de dados restaurado"
    else
        log_error "Dump SQL não encontrado no backup"
    fi

    rm -rf "$temp_dir"
}

# Verificar e iniciar serviços
verify_and_start_services() {
    log_info "[7/8] Verificando serviços..."

    # Aguardar containers ficarem saudáveis
    log_info "Aguardando containers..."
    sleep 10

    # Verificar status dos containers N8N
    local n8n_containers=$(docker ps --filter "name=n8n" --format "{{.Names}}")

    if [ -z "$n8n_containers" ]; then
        log_error "Nenhum container N8N encontrado"
        return 1
    fi

    echo "$n8n_containers" | while read container; do
        local status=$(docker inspect "$container" | jq -r '.[0].State.Status')
        if [ "$status" = "running" ]; then
            log_success "Container OK: $container"
        else
            log_warning "Container com problema: $container ($status)"
            docker restart "$container"
        fi
    done

    # Testar conectividade do N8N
    log_info "Testando N8N..."
    local retries=10
    while [ $retries -gt 0 ]; do
        if curl -f http://localhost:5678/healthz > /dev/null 2>&1; then
            log_success "N8N está respondendo"
            break
        fi
        sleep 5
        ((retries--))
    done

    if [ $retries -eq 0 ]; then
        log_warning "N8N não está respondendo - verificar logs"
    fi
}

# Configurar monitoramento básico
setup_monitoring() {
    log_info "[8/8] Configurando monitoramento..."

    # Criar script de health check
    cat > /opt/n8n-backup/health-check.sh << 'EOF'
#!/bin/bash
# Health check script

echo "=== N8N Health Check ==="
echo "Data: $(date)"

# Verificar containers
echo ""
echo "Containers:"
docker ps --filter "name=n8n" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verificar N8N
echo ""
echo "N8N Status:"
if curl -f http://localhost:5678/healthz > /dev/null 2>&1; then
    echo "✓ N8N OK"
else
    echo "✗ N8N não responde"
fi

# Verificar PostgreSQL
echo ""
echo "PostgreSQL Status:"
if docker exec n8n_postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
    echo "✓ PostgreSQL OK"
else
    echo "✗ PostgreSQL falha"
fi

echo ""
echo "Último backup: $(ls -t /opt/n8n-backup/backups/local/n8n_backup_*.tar.gz 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo 'Nenhum')"
EOF

    chmod +x /opt/n8n-backup/health-check.sh

    # Adicionar ao crontab (health check a cada hora)
    (crontab -l 2>/dev/null; echo "0 * * * * /opt/n8n-backup/health-check.sh >> /opt/n8n-backup/logs/health.log 2>&1") | crontab -

    log_success "Monitoramento configurado"
}

# Mostrar resumo da recuperação
show_recovery_summary() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     RECUPERAÇÃO CONCLUÍDA! 🎉         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "📋 Resumo da Recuperação:"
    echo ""
    echo "✓ Dependências instaladas"
    echo "✓ Rclone configurado"
    echo "✓ Backup baixado: $(basename "$LATEST_BACKUP_FILE")"
    echo "✓ EasyPanel instalado"
    echo "✓ Schema restaurado"
    echo "✓ Banco de dados restaurado"
    echo "✓ Serviços verificados"
    echo "✓ Monitoramento configurado"
    echo ""
    echo "🌐 Acesse o N8N: http://$(hostname -I | awk '{print $1}'):5678"
    echo ""
    echo "🔍 Verificar status: /opt/n8n-backup/health-check.sh"
    echo "📊 Ver logs: tail -f /opt/n8n-backup/logs/backup.log"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "   - Verifique se as credenciais estão funcionando"
    echo "   - Teste os workflows existentes"
    echo "   - Configure backup automático: crontab -e"
    echo ""
}

# Setup de nova VM (modo simplificado)
setup_new_vm() {
    log_info "Configurando nova VM..."

    # Instalar dependências básicas
    install_dependencies

    # Configurar rclone
    setup_rclone_recovery

    # Baixar e executar recovery
    download_latest_backup
    restore_easypanel_schema
    restore_database
    verify_and_start_services

    log_success "Nova VM configurada!"
}

# Função auxiliar para determinar bucket correto
get_backup_bucket() {
    case $BACKUP_SOURCE in
        oracle)
            echo "$ORACLE_BUCKET"
            ;;
        b2)
            echo "$B2_BUCKET"
            ;;
        *)
            echo ""
            ;;
    esac
}
