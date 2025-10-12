#!/bin/bash
# ============================================
# Funções PostgreSQL
# Arquivo: /opt/n8n-backup/lib/postgres.sh
# ============================================

# Variável de conexão PostgreSQL
export PGPASSWORD="${N8N_POSTGRES_PASSWORD}"

# Nome do container PostgreSQL (EasyPanel)
POSTGRES_CONTAINER=$(docker ps --filter "name=n8n_postgres" --format "{{.Names}}" | head -1)

# Testar conexão com PostgreSQL
test_postgres_connection() {
    log_info "Testando conexão com PostgreSQL..."
    
    if docker exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -c "SELECT 1" > /dev/null 2>&1; then
        log_success "Conexão com PostgreSQL OK"
        return 0
    else
        log_error "Falha ao conectar com PostgreSQL"
        log_error "Verifique se o container '${POSTGRES_CONTAINER}' está rodando"
        return 1
    fi
}

# Backup completo do PostgreSQL
backup_postgres_full() {
    local output_file=$1
    
    log_info "Iniciando backup completo do PostgreSQL..."
    
    if [ "$PARALLEL_COMPRESSION" = true ] && command -v pigz &> /dev/null; then
        docker exec "${POSTGRES_CONTAINER}" pg_dump \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            --no-owner --no-acl \
            | pigz -${COMPRESSION_LEVEL} > "${output_file}"
    else
        docker exec "${POSTGRES_CONTAINER}" pg_dump \
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
    
    local temp_dump=$(mktemp)
    
    # Backup de todas as tabelas exceto execution_entity
    docker exec "${POSTGRES_CONTAINER}" pg_dump \
        -U "${N8N_POSTGRES_USER}" \
        -d "${N8N_POSTGRES_DB}" \
        --no-owner --no-acl \
        --exclude-table=execution_entity \
        > "${temp_dump}"
    
    # Adicionar executions dos últimos X dias
    docker exec "${POSTGRES_CONTAINER}" psql \
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
    
    # Descompactar e restaurar
    if [[ "$backup_file" == *.gz ]]; then
        gunzip < "${backup_file}" | docker exec -i "${POSTGRES_CONTAINER}" psql \
            -U "${N8N_POSTGRES_USER}" \
            -d "${N8N_POSTGRES_DB}" \
            > /dev/null 2>&1
    else
        docker exec -i "${POSTGRES_CONTAINER}" psql \
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
    
    local temp_dir=$(mktemp -d)
    
    # Extrair dump
    gunzip < "${backup_file}" > "${temp_dir}/dump.sql"
    
    # Extrair apenas o workflow específico
    grep -A 50 "INSERT INTO public.workflow_entity.*'${workflow_name}'" "${temp_dir}/dump.sql" > "${temp_dir}/workflow.sql"
    
    if [ -s "${temp_dir}/workflow.sql" ]; then
        docker exec -i "${POSTGRES_CONTAINER}" psql \
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
    
    local temp_dir=$(mktemp -d)
    
    # Extrair dump
    gunzip < "${backup_file}" > "${temp_dir}/dump.sql"
    
    # Extrair apenas a credencial específica
    grep -A 20 "INSERT INTO public.credentials_entity.*'${credential_name}'" "${temp_dir}/dump.sql" > "${temp_dir}/credential.sql"
    
    if [ -s "${temp_dir}/credential.sql" ]; then
        docker exec -i "${POSTGRES_CONTAINER}" psql \
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
    docker exec "${POSTGRES_CONTAINER}" psql \
        -U "${N8N_POSTGRES_USER}" \
        -d "${N8N_POSTGRES_DB}" \
        -c "\dt" 2>/dev/null | grep public | awk '{print $3}'
}

# Estatísticas do banco
get_postgres_stats() {
    local workflows=$(docker exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM workflow_entity" 2>/dev/null | xargs)
    local credentials=$(docker exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM credentials_entity" 2>/dev/null | xargs)
    local executions=$(docker exec "${POSTGRES_CONTAINER}" psql -U "${N8N_POSTGRES_USER}" -d "${N8N_POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM execution_entity" 2>/dev/null | xargs)
    
    echo "Workflows: ${workflows}"
    echo "Credenciais: ${credentials}"
    echo "Executions: ${executions}"
}