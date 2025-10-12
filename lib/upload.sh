#!/bin/bash
# ============================================
# Funções de Upload para Cloud Storage
# Arquivo: /opt/n8n-backup/lib/upload.sh
# ============================================

# Configurar Oracle Object Storage via rclone
setup_oracle_storage() {
    log_info "Configurando Oracle Object Storage..."
    
    if rclone listremotes | grep -q "^oracle:"; then
        log_success "Oracle já configurado"
        return 0
    fi
    
    # Verificar se temos as credenciais necessárias
    if [ -z "$ORACLE_NAMESPACE" ] || [ "$ORACLE_NAMESPACE" = "seu-namespace" ]; then
        log_error "Oracle não configurado no config.env"
        return 1
    fi
    
    # Criar configuração do rclone
    cat >> ~/.config/rclone/rclone.conf << EOF

[oracle]
type = swift
env_auth = false
user = ${ORACLE_NAMESPACE}
key = ${ORACLE_COMPARTMENT_ID}
auth = https://swiftobjectstorage.${ORACLE_REGION}.oraclecloud.com/auth/v1.0
tenant = ${ORACLE_NAMESPACE}
region = ${ORACLE_REGION}
EOF
    
    log_success "Oracle configurado no rclone"
}

# Configurar Backblaze B2 via rclone
setup_b2_storage() {
    log_info "Configurando Backblaze B2..."
    
    if rclone listremotes | grep -q "^b2:"; then
        log_success "B2 já configurado"
        return 0
    fi
    
    # Verificar credenciais
    if [ -z "$B2_ACCOUNT_ID" ] || [ "$B2_ACCOUNT_ID" = "sua-account-id" ]; then
        log_error "B2 não configurado no config.env"
        return 1
    fi
    
    # Criar configuração do rclone
    cat >> ~/.config/rclone/rclone.conf << EOF

[b2]
type = b2
account = ${B2_ACCOUNT_ID}
key = ${B2_APPLICATION_KEY}
hard_delete = false
EOF
    
    log_success "B2 configurado no rclone"
}

# Criar bucket se não existir (Oracle)
create_oracle_bucket() {
    local bucket_name=$1
    
    log_info "Verificando bucket Oracle: ${bucket_name}"
    
    if rclone lsd "oracle:" | grep -q "${bucket_name}"; then
        log_success "Bucket já existe"
        return 0
    fi
    
    log_info "Criando bucket: ${bucket_name}"
    rclone mkdir "oracle:${bucket_name}"
    
    if [ $? -eq 0 ]; then
        log_success "Bucket criado"
        return 0
    else
        log_error "Falha ao criar bucket"
        return 1
    fi
}

# Criar bucket se não existir (B2)
create_b2_bucket() {
    local bucket_name=$1
    
    log_info "Verificando bucket B2: ${bucket_name}"
    
    if rclone lsd "b2:" | grep -q "${bucket_name}"; then
        log_success "Bucket já existe"
        return 0
    fi
    
    log_info "Criando bucket: ${bucket_name}"
    rclone mkdir "b2:${bucket_name}"
    
    if [ $? -eq 0 ]; then
        log_success "Bucket criado"
        return 0
    else
        log_error "Falha ao criar bucket"
        return 1
    fi
}

# Upload com retry e verificação
upload_with_retry() {
    local file=$1
    local destination=$2
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        log_info "Tentativa $((retry+1)) de ${max_retries}..."
        
        rclone copy "$file" "$destination" --progress
        
        if [ $? -eq 0 ]; then
            # Verificar se o arquivo foi realmente enviado
            local filename=$(basename "$file")
            if rclone ls "$destination" | grep -q "$filename"; then
                log_success "Upload verificado com sucesso"
                return 0
            fi
        fi
        
        retry=$((retry+1))
        if [ $retry -lt $max_retries ]; then
            log_warning "Falha no upload. Tentando novamente em 5s..."
            sleep 5
        fi
    done
    
    log_error "Falha no upload após ${max_retries} tentativas"
    return 1
}

# Verificar integridade após upload
verify_upload() {
    local local_file=$1
    local remote_path=$2
    
    log_info "Verificando integridade do upload..."
    
    local local_size=$(stat -c%s "$local_file")
    local remote_size=$(rclone size "$remote_path" --json | jq -r '.bytes')
    
    if [ "$local_size" -eq "$remote_size" ]; then
        log_success "Integridade verificada (${local_size} bytes)"
        return 0
    else
        log_error "Tamanhos não conferem! Local: ${local_size}, Remoto: ${remote_size}"
        return 1
    fi
}

# Listar backups remotos
list_remote_backups() {
    local remote=$1
    local bucket=$2
    
    rclone lsl "${remote}:${bucket}/" | grep "n8n_backup_" | sort -r
}

# Baixar backup remoto
download_backup() {
    local remote=$1
    local bucket=$2
    local filename=$3
    local destination=$4
    
    log_info "Baixando ${filename}..."
    
    rclone copy "${remote}:${bucket}/${filename}" "$destination" --progress
    
    if [ $? -eq 0 ]; then
        log_success "Download concluído"
        return 0
    else
        log_error "Falha no download"
        return 1
    fi
}

# Deletar backups antigos (retenção)
cleanup_remote_storage() {
    local remote=$1
    local bucket=$2
    local retention_days=$3
    
    log_info "Limpando backups com mais de ${retention_days} dias..."
    
    local cutoff_date=$(date -d "${retention_days} days ago" +%s)
    local deleted_count=0
    
    while IFS= read -r line; do
        local filename=$(echo "$line" | awk '{print $NF}')
        local file_date=$(echo "$filename" | grep -oP '\d{4}-\d{2}-\d{2}')
        
        if [ -n "$file_date" ]; then
            local file_timestamp=$(date -d "$file_date" +%s)
            
            if [ "$file_timestamp" -lt "$cutoff_date" ]; then
                log_info "Deletando: ${filename}"
                rclone delete "${remote}:${bucket}/${filename}"
                deleted_count=$((deleted_count+1))
            fi
        fi
    done < <(rclone lsl "${remote}:${bucket}/" | grep "n8n_backup_")
    
    log_success "Deletados ${deleted_count} backups antigos"
}

# Sincronizar entre storages (Oracle -> B2 como exemplo)
sync_between_storages() {
    local source_remote=$1
    local source_bucket=$2
    local dest_remote=$3
    local dest_bucket=$4
    
    log_info "Sincronizando de ${source_remote} para ${dest_remote}..."
    
    rclone sync "${source_remote}:${source_bucket}/" "${dest_remote}:${dest_bucket}/" \
        --include "n8n_backup_*.tar.gz" \
        --progress
    
    if [ $? -eq 0 ]; then
        log_success "Sincronização concluída"
        return 0
    else
        log_error "Falha na sincronização"
        return 1
    fi
}

# Calcular custos estimados
estimate_storage_costs() {
    local remote=$1
    local bucket=$2
    
    log_info "Calculando custos de storage em ${remote}..."
    
    local total_bytes=$(rclone size "${remote}:${bucket}/" --json | jq -r '.bytes')
    local total_gb=$(awk "BEGIN {printf \"%.2f\", $total_bytes/1073741824}")
    
    case $remote in
        oracle)
            local cost=$(awk "BEGIN {printf \"%.2f\", $total_gb * 0.0255}")
            echo "Oracle Object Storage: ${total_gb}GB = \$${cost}/mês"
            ;;
        b2)
            local cost=$(awk "BEGIN {printf \"%.2f\", $total_gb * 0.006}")
            echo "Backblaze B2: ${total_gb}GB = \$${cost}/mês"
            ;;
    esac
}

# Status geral dos backups
backup_status_report() {
    echo "╔════════════════════════════════════════╗"
    echo "║     STATUS DOS BACKUPS                 ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # Local
    local local_count=$(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" | wc -l)
    local local_size=$(du -sh "${BACKUP_LOCAL_DIR}" 2>/dev/null | cut -f1)
    echo "📁 Local: ${local_count} backups (${local_size})"
    
    # Oracle
    if [ "$ORACLE_ENABLED" = true ]; then
        local oracle_count=$(rclone lsl "oracle:${ORACLE_BUCKET}/" 2>/dev/null | grep -c "n8n_backup_" || echo "0")
        echo "☁️  Oracle: ${oracle_count} backups"
        estimate_storage_costs "oracle" "${ORACLE_BUCKET}"
    fi
    
    # B2
    if [ "$B2_ENABLED" = true ]; then
        local b2_count=$(rclone lsl "b2:${B2_BUCKET}/" 2>/dev/null | grep -c "n8n_backup_" || echo "0")
        echo "🔐 B2 (Offsite): ${b2_count} backups"
        estimate_storage_costs "b2" "${B2_BUCKET}"
    fi
    
    echo ""
    echo "Último backup: $(ls -t ${BACKUP_LOCAL_DIR}/n8n_backup_*.tar.gz 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo 'Nenhum')"
}