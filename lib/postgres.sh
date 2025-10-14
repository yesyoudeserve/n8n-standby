#!/bin/bash
# ============================================
# Funções PostgreSQL
# Arquivo: /opt/n8n-backup/lib/postgres.sh
# Versão: 2.1 - Compatível com sudo
# ============================================

# Variável de conexão PostgreSQL
export PGPASSWORD="${N8N_POSTGRES_PASSWORD}"

# Função para detectar se deve usar sudo
should_use_sudo_docker() {
    if ! docker ps > /dev/null 2>&1; then
        if sudo docker ps > /dev/null 2>&1; then
            return 0  # Deve usar sudo
        fi
    fi
    return 1  # Não precisa sudo
}

# Função wrapper para comandos Docker
docker_cmd() {
    if should_use_sudo_docker; then
        sudo docker "$@"
    else
        docker "$@"
    fi
}

# Detectar container PostgreSQL automaticamente
detect_postgres_container() {
    local container=""
    
    # Tentar sem sudo
    container=$(docker ps --filter "name=postgres" --format "{{.Names}}" 2>/dev/null | grep -i postgres | head -1)
    
    # Se não encontrou, tentar com sudo
    if [ -z "$container" ]; then
        container=$(sudo docker ps --filter "name=postgres" --format "{{.Names}}" 2>/dev/null | grep -i postgres | head -1)
    fi
    
    # Se ainda não encontrou, tentar nomes alternativos
    if [ -z "$container" ]; then
        for name in n8n_postgres n8n-postgres postgres-n8n postgresql; do
            container=$(docker_cmd ps --filter "name=$name" --format "{{.Names}}" 2>/dev/null | head -1)
            [ -n "$container" ] && break
        done
    fi
    
    echo "$container"
}

# Nome do container PostgreSQL (detectado automaticamente)
POSTGRES_CONTAINER=$(detect_postgres_container)

# Atualizar container se não foi detectado
update_postgres_container() {
    POSTGRES_CONTAINER=$(detect_postgres_container)
}

# Testar conexão com PostgreSQL
test_postgres_connection() {
    log_info "Testando conexão com PostgreSQL..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        log_info "Containers disponíveis:"
        docker_cmd ps --format "table {{.Names}}\t{{.Status}}"
        return 1
    fi
    
    if docker_cmd exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -c "SELECT 1" > /dev/null 2>&1; then
        log_success "Conexão com PostgreSQL OK"
        return 0
    else
        log_error "Falha ao conectar com PostgreSQL"
        log_error "Verifique se o container '${POSTGRES_CONTAINER}' está rodando"
        log_info "Status do container:"
        docker_cmd ps -a --filter "name=${POSTGRES_CONTAINER}" --format "table {{.Names}}\t{{.Status}}"
        return 1
    fi
}

# Backup completo do PostgreSQL
backup_postgres_full() {
    local output_file=$1
    
    log_info "Iniciando backup completo do PostgreSQL..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    if [ "$PARALLEL_COMPRESSION" = true ] && command -v pigz &> /dev/null; then
        docker_cmd exec "${POSTGRES_CONTAINER}" pg_dump \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            --no-owner --no-acl \
            | pigz -${COMPRESSION_LEVEL} > "${output_file}"
    else
        docker_cmd exec "${POSTGRES_CONTAINER}" pg_dump \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            --no-owner --no-acl \
            | gzip -${COMPRESSION_LEVEL} > "${output_file}"
    fi
    
    if [ $? -eq 0 ]; then
        file_size=$(stat -c%s "${output_file}")
        if [ "$file_size" -ge 1073741824 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
        elif [ "$file_size" -ge 1048576 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
        elif [ "$file_size" -ge 1024 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
        else
            size_display="${file_size}B"
        fi
        log_success "Backup PostgreSQL completo: ${size_display}"
        return 0
    else
        log_error "Falha no backup PostgreSQL"
        return 1
    fi
}

# Backup seletivo (últimos X dias de executions)
backup_postgres_selective() {
    local output_file=$1
    local days=${BACKUP_EXECUTIONS_DAYS:-7}
    
    log_info "Iniciando backup seletivo (executions dos últimos ${days} dias)..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    local temp_dump=$(mktemp)
    
    # Backup de todas as tabelas exceto execution_entity
    docker_cmd exec "${POSTGRES_CONTAINER}" pg_dump \
        -U "${N8N_POSTGRES_USER}" \
        -d "${N8N_POSTGRES_DB}" \
        --no-owner --no-acl \
        --exclude-table=execution_entity \
        > "${temp_dump}"
    
    # Adicionar executions dos últimos X dias
    docker_cmd exec "${POSTGRES_CONTAINER}" psql \
        -U "${N8N_POSTGRES_USER}" \
        -d "${N8N_POSTGRES_DB}" \
        -t -c "COPY (SELECT * FROM execution_entity WHERE \"startedAt\" >= NOW() - INTERVAL '${days} days') TO STDOUT" \
        >> "${temp_dump}" 2>/dev/null || true
    
    # Comprimir
    if [ "$PARALLEL_COMPRESSION" = true ] && command -v pigz &> /dev/null; then
        pigz -${COMPRESSION_LEVEL} < "${temp_dump}" > "${output_file}"
    else
        gzip -${COMPRESSION_LEVEL} < "${temp_dump}" > "${output_file}"
    fi
    
    rm -f "${temp_dump}"
    
    if [ $? -eq 0 ]; then
        file_size=$(stat -c%s "${output_file}")
        if [ "$file_size" -ge 1073741824 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
        elif [ "$file_size" -ge 1048576 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
        elif [ "$file_size" -ge 1024 ]; then
            size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
        else
            size_display="${file_size}B"
        fi
        log_success "Backup PostgreSQL seletivo: ${size_display}"
        return 0
    else
        log_error "Falha no backup PostgreSQL seletivo"
        return 1
    fi
}

# Restaurar banco completo
restore_postgres_full() {
    local backup_file=$1
    
    if ! confirm "ATENÇÃO: Isso irá SOBRESCREVER todos os dados do banco. Continuar?" "n"; then
        log_warning "Restauração cancelada pelo usuário"
        return 1
    fi
    
    log_info "Restaurando banco completo..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    # Descompactar e restaurar
    if [[ "$backup_file" == *.gz ]]; then
        gunzip < "${backup_file}" | docker_cmd exec -i "${POSTGRES_CONTAINER}" psql \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            > /dev/null 2>&1
    else
        docker_cmd exec -i "${POSTGRES_CONTAINER}" psql \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            < "${backup_file}" > /dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Banco restaurado com sucesso"
        return 0
    else
        log_error "Falha na restauração do banco"
        return 1
    fi
}

# Restaurar workflow específico
restore_workflow() {
    local backup_file=$1
    local workflow_name=$2
    
    log_info "Restaurando workflow: ${workflow_name}..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    local temp_dir=$(mktemp -d)
    
    # Extrair dump
    gunzip < "${backup_file}" > "${temp_dir}/dump.sql"
    
    # Extrair apenas o workflow específico
    grep -A 50 "INSERT INTO public.workflow_entity.*'${workflow_name}'" "${temp_dir}/dump.sql" > "${temp_dir}/workflow.sql"
    
    if [ -s "${temp_dir}/workflow.sql" ]; then
        docker_cmd exec -i "${POSTGRES_CONTAINER}" psql \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            < "${temp_dir}/workflow.sql" > /dev/null 2>&1
        
        log_success "Workflow '${workflow_name}' restaurado"
    else
        log_error "Workflow não encontrado no backup"
    fi
    
    rm -rf "${temp_dir}"
}

# Restaurar credencial específica
restore_credential() {
    local backup_file=$1
    local credential_name=$2
    
    log_info "Restaurando credencial: ${credential_name}..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    local temp_dir=$(mktemp -d)
    
    # Extrair dump
    gunzip < "${backup_file}" > "${temp_dir}/dump.sql"
    
    # Extrair apenas a credencial específica
    grep -A 20 "INSERT INTO public.credentials_entity.*'${credential_name}'" "${temp_dir}/dump.sql" > "${temp_dir}/credential.sql"
    
    if [ -s "${temp_dir}/credential.sql" ]; then
        docker_cmd exec -i "${POSTGRES_CONTAINER}" psql \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            < "${temp_dir}/credential.sql" > /dev/null 2>&1
        
        log_success "Credencial '${credential_name}' restaurada"
    else
        log_error "Credencial não encontrada no backup"
    fi
    
    rm -rf "${temp_dir}"
}

# Listar tabelas do banco
list_postgres_tables() {
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    docker_cmd exec "${POSTGRES_CONTAINER}" psql \
        -U "${N8N_POSTGRES_USER}" \
        -d "${N8N_POSTGRES_DB}" \
        -c "\dt" 2>/dev/null | grep public | awk '{print $3}'
}

# Estatísticas do banco
get_postgres_stats() {
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        echo "Container PostgreSQL não encontrado"
        return 1
    fi
    
    local workflows=$(docker_cmd exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM workflow_entity" 2>/dev/null | xargs)
    local credentials=$(docker_cmd exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM credentials_entity" 2>/dev/null | xargs)
    local executions=$(docker_cmd exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM execution_entity" 2>/dev/null | xargs)
    
    echo "Workflows: ${workflows}"
    echo "Credenciais: ${credentials}"
    echo "Executions: ${executions}"
}

# Verificar saúde do PostgreSQL
check_postgres_health() {
    log_info "Verificando saúde do PostgreSQL..."
    
    # Atualizar container
    update_postgres_container
    
    if [ -z "$POSTGRES_CONTAINER" ]; then
        log_error "Container PostgreSQL não encontrado"
        return 1
    fi
    
    # Verificar se container está rodando
    local status=$(docker_cmd inspect "$POSTGRES_CONTAINER" 2>/dev/null | jq -r '.[0].State.Status')
    
    if [ "$status" != "running" ]; then
        log_error "Container PostgreSQL não está rodando (status: $status)"
        return 1
    fi
    
    # Verificar conectividade
    if ! docker_cmd exec "$POSTGRES_CONTAINER" psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
        log_error "PostgreSQL não está aceitando conexões"
        return 1
    fi
    
    # Verificar banco N8N
    if ! docker_cmd exec "$POSTGRES_CONTAINER" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -c "SELECT 1" > /dev/null 2>&1; then
        log_error "Banco N8N não está acessível"
        return 1
    fi
    
    log_success "PostgreSQL está saudável"
    return 0
}