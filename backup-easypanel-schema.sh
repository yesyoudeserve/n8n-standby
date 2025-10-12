#!/bin/bash
# ============================================
# Backup Completo do Schema EasyPanel
# Arquivo: /opt/n8n-backup/backup-easypanel-schema.sh
# Execute MANUALMENTE para salvar toda estrutura
# ============================================

set -euo pipefail

# Configuração
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/opt/n8n-backup/logs/easypanel_backup.log"
mkdir -p /opt/n8n-backup/logs

source "${SCRIPT_DIR}/lib/logger.sh"

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/opt/n8n-backup/easypanel_schema_${TIMESTAMP}"

show_banner
log_info "Backup COMPLETO do Schema EasyPanel"
echo ""

mkdir -p "${BACKUP_DIR}"

# 1. Exportar TODOS os containers relacionados ao N8N
log_info "[1/8] Exportando containers N8N..."
docker ps -a --filter "name=n8n" --format "{{.Names}}" > "${BACKUP_DIR}/container_list.txt"

while read container; do
    log_info "  → ${container}"
    
    # Configuração completa do container
    docker inspect "$container" > "${BACKUP_DIR}/${container}_full_inspect.json"
    
    # Comando de criação (docker run equivalente)
    docker inspect "$container" | jq -r '.[0]' > "${BACKUP_DIR}/${container}_config.json"
    
done < "${BACKUP_DIR}/container_list.txt"

# 2. Exportar containers auxiliares (postgres, redis)
log_info "[2/8] Exportando containers auxiliares..."
for service in postgres redis pgadmin; do
    if docker ps -a --format "{{.Names}}" | grep -q "$service"; then
        container=$(docker ps -a --filter "name=$service" --format "{{.Names}}" | head -1)
        log_info "  → ${container}"
        docker inspect "$container" > "${BACKUP_DIR}/${service}_full_inspect.json"
    fi
done

# 3. Exportar networks
log_info "[3/8] Exportando Docker networks..."
docker network ls --format "{{.Name}}" | grep -v -E "^(bridge|host|none)$" > "${BACKUP_DIR}/networks_list.txt"

while read network; do
    log_info "  → ${network}"
    docker network inspect "$network" > "${BACKUP_DIR}/network_${network}.json"
done < "${BACKUP_DIR}/networks_list.txt"

# 4. Exportar volumes
log_info "[4/8] Exportando Docker volumes..."
docker volume ls --format "{{.Name}}" | grep -E "(n8n|postgres|redis)" > "${BACKUP_DIR}/volumes_list.txt" || echo "" > "${BACKUP_DIR}/volumes_list.txt"

while read volume; do
    if [ -n "$volume" ]; then
        log_info "  → ${volume}"
        docker volume inspect "$volume" > "${BACKUP_DIR}/volume_${volume}.json"
    fi
done < "${BACKUP_DIR}/volumes_list.txt"

# 5. Localizar e copiar arquivos do EasyPanel (AGORA CRIPTOGRAFADO!)
log_info "[5/8] Procurando arquivos de configuração EasyPanel..."

EASYPANEL_PATHS=(
    "/etc/easypanel"
    "$HOME/.easypanel"
    "/opt/easypanel"
    "/var/lib/easypanel"
    "/usr/local/easypanel"
)

for path in "${EASYPANEL_PATHS[@]}"; do
    if [ -d "$path" ]; then
        log_success "  ✓ Encontrado: $path"
        # Copiar e depois criptografar
        temp_dir="${BACKUP_DIR}/easypanel_$(basename $path)"
        cp -r "$path" "$temp_dir" 2>/dev/null || \
            log_warning "  ⚠ Sem permissão para copiar: $path"

        # Criptografar arquivos sensíveis
        if [ -d "$temp_dir" ]; then
            find "$temp_dir" -type f \( -name "*.env" -o -name "*.json" -o -name "*.yml" -o -name "*.yaml" \) | while read file; do
                if [ -f "$file" ]; then
                    log_info "  🔐 Criptografando: $(basename "$file")"
                    # Usar função de criptografia do security.sh
                    source "${SCRIPT_DIR}/lib/security.sh"
                    load_encryption_key > /dev/null 2>&1
                    encrypt_file "$file" "${file}.enc"
                    rm "$file"
                fi
            done
        fi
    fi
done

# 6. Procurar docker-compose.yml
log_info "[6/8] Procurando docker-compose.yml..."

COMPOSE_PATHS=(
    "/opt/easypanel/projects/n8n/docker-compose.yml"
    "/var/lib/easypanel/projects/n8n/docker-compose.yml"
    "$HOME/easypanel/projects/n8n/docker-compose.yml"
    "/opt/n8n/docker-compose.yml"
)

for path in "${COMPOSE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        log_success "  ✓ Encontrado: $path"
        cp "$path" "${BACKUP_DIR}/docker-compose.yml"
        
        # Copiar diretório inteiro do projeto
        project_dir=$(dirname "$path")
        if [ -d "$project_dir" ]; then
            cp -r "$project_dir" "${BACKUP_DIR}/project_directory" 2>/dev/null || true
        fi
        break
    fi
done

# 7. Gerar script de recriação automática
log_info "[7/8] Gerando scripts de recriação..."

cat > "${BACKUP_DIR}/RECREATE.sh" << 'EOF'
#!/bin/bash
# ============================================
# Script de Recriação Automática
# Gerado em: TIMESTAMP_PLACEHOLDER
# ============================================

set -e

echo "╔════════════════════════════════════════╗"
echo "║   Recriação da Estrutura N8N           ║"
echo "╚════════════════════════════════════════╝"
echo ""

# 1. Recriar networks
echo "[1/4] Recriando networks..."
EOF

# Adicionar comandos para recriar networks
while read network; do
    driver=$(jq -r '.[0].Driver // .Driver // "bridge"' "${BACKUP_DIR}/network_${network}.json" 2>/dev/null || echo "bridge")
    echo "docker network create --driver ${driver} ${network} 2>/dev/null || true" >> "${BACKUP_DIR}/RECREATE.sh"
done < "${BACKUP_DIR}/networks_list.txt"

cat >> "${BACKUP_DIR}/RECREATE.sh" << 'EOF'

# 2. Recriar volumes (se necessário)
echo "[2/4] Verificando volumes..."
EOF

# Adicionar comandos para volumes
if [ -s "${BACKUP_DIR}/volumes_list.txt" ]; then
    while read volume; do
        if [ -n "$volume" ]; then
            echo "docker volume create ${volume} 2>/dev/null || true" >> "${BACKUP_DIR}/RECREATE.sh"
        fi
    done < "${BACKUP_DIR}/volumes_list.txt"
fi

cat >> "${BACKUP_DIR}/RECREATE.sh" << 'EOF'

# 3. Recriar containers
echo "[3/4] Recriando containers..."
EOF

# Gerar comandos docker run para cada container
while read container; do
    image=$(jq -r '.[0].Config.Image' "${BACKUP_DIR}/${container}_full_inspect.json")
    network=$(jq -r '.[0].NetworkSettings.Networks | keys[0]' "${BACKUP_DIR}/${container}_full_inspect.json")
    
    echo "" >> "${BACKUP_DIR}/RECREATE.sh"
    echo "# Container: ${container}" >> "${BACKUP_DIR}/RECREATE.sh"
    echo "docker run -d \\" >> "${BACKUP_DIR}/RECREATE.sh"
    echo "  --name ${container} \\" >> "${BACKUP_DIR}/RECREATE.sh"
    echo "  --network ${network} \\" >> "${BACKUP_DIR}/RECREATE.sh"
    
    # Variáveis de ambiente
    jq -r '.[0].Config.Env[]' "${BACKUP_DIR}/${container}_full_inspect.json" | while read env; do
        echo "  -e \"${env}\" \\" >> "${BACKUP_DIR}/RECREATE.sh"
    done
    
    # Volumes
    jq -r '.[0].Mounts[] | "-v \(.Source):\(.Destination)"' "${BACKUP_DIR}/${container}_full_inspect.json" | while read vol; do
        echo "  ${vol} \\" >> "${BACKUP_DIR}/RECREATE.sh"
    done
    
    # Portas
    jq -r '.[0].NetworkSettings.Ports | to_entries[] | select(.value != null) | "-p \(.value[0].HostPort):\(.key)"' "${BACKUP_DIR}/${container}_full_inspect.json" 2>/dev/null | while read port; do
        echo "  ${port} \\" >> "${BACKUP_DIR}/RECREATE.sh"
    done || true
    
    # Labels (importante para EasyPanel!)
    jq -r '.[0].Config.Labels | to_entries[] | "--label \"\(.key)=\(.value)\""' "${BACKUP_DIR}/${container}_full_inspect.json" | while read label; do
        echo "  ${label} \\" >> "${BACKUP_DIR}/RECREATE.sh"
    done
    
    echo "  ${image}" >> "${BACKUP_DIR}/RECREATE.sh"
    
done < "${BACKUP_DIR}/container_list.txt"

cat >> "${BACKUP_DIR}/RECREATE.sh" << 'EOF'

# 4. Verificação
echo "[4/4] Verificando containers..."
docker ps -a --filter "name=n8n"

echo ""
echo "✓ Recriação concluída!"
echo "  Execute: docker logs n8n-main"
EOF

chmod +x "${BACKUP_DIR}/RECREATE.sh"

# Substituir placeholder
sed -i "s/TIMESTAMP_PLACEHOLDER/${TIMESTAMP}/" "${BACKUP_DIR}/RECREATE.sh"

# 8. Criar README com instruções
log_info "[8/8] Criando documentação..."

cat > "${BACKUP_DIR}/README.md" << 'EOF'
# Backup Completo do Schema EasyPanel N8N

Este backup contém TODA a estrutura necessária para recriar o ambiente N8N.

## 📁 Conteúdo

- `*_full_inspect.json` - Configuração completa de cada container
- `network_*.json` - Configuração das Docker networks
- `volume_*.json` - Informações dos volumes
- `easypanel_*` - Arquivos de configuração do EasyPanel
- `docker-compose.yml` - Compose file original (se encontrado)
- `RECREATE.sh` - Script automático de recriação

## 🔄 Como Restaurar

### Opção 1: Via EasyPanel (Recomendado)
1. Instale EasyPanel na nova VM
2. Use os arquivos JSON para recriar os serviços manualmente
3. Copie as variáveis de ambiente de `*_config.json`

### Opção 2: Via Docker Compose
```bash
# Se docker-compose.yml existe neste backup:
docker-compose up -d
```

### Opção 3: Script Automático
```bash
chmod +x RECREATE.sh
./RECREATE.sh
```

### Opção 4: Manual
Consulte os arquivos `*_full_inspect.json` para ver a configuração
completa de cada container e recrie manualmente.

## ⚠️ IMPORTANTE

Após recriar os containers, você ainda precisa:
1. Restaurar o banco PostgreSQL: `/opt/n8n-backup/restore.sh`
2. Verificar se as credenciais do N8N estão corretas
3. Reiniciar os containers: `docker restart n8n-main n8n-worker n8n-webhook`

## 📝 Containers Incluídos

EOF

cat "${BACKUP_DIR}/container_list.txt" >> "${BACKUP_DIR}/README.md"

echo "" >> "${BACKUP_DIR}/README.md"
echo "Data do backup: ${TIMESTAMP}" >> "${BACKUP_DIR}/README.md"

# Comprimir tudo
log_info "Comprimindo backup do schema..."
tar -czf "${BACKUP_DIR}.tar.gz" -C "$(dirname ${BACKUP_DIR})" "$(basename ${BACKUP_DIR})"

# Upload para storages (igual ao backup principal)
if [ "$ORACLE_ENABLED" = true ]; then
    log_info "Fazendo upload para Oracle..."
    rclone copy "${BACKUP_DIR}.tar.gz" "oracle:${ORACLE_BUCKET}/schemas/" --quiet
fi

if [ "$B2_ENABLED" = true ]; then
    log_info "Fazendo upload para B2..."
    rclone copy "${BACKUP_DIR}.tar.gz" "b2:${B2_BUCKET}/schemas/" --quiet
fi

# Limpeza
rm -rf "${BACKUP_DIR}"

file_size=$(stat -c%s "${BACKUP_DIR}.tar.gz")
if [ "$file_size" -ge 1073741824 ]; then
    size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1073741824}")GB"
elif [ "$file_size" -ge 1048576 ]; then
    size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1048576}")MB"
elif [ "$file_size" -ge 1024 ]; then
    size_display="$(awk "BEGIN {printf \"%.2f\", $file_size/1024}")KB"
else
    size_display="${file_size}B"
fi

echo ""
log_success "╔════════════════════════════════════════╗"
log_success "║   BACKUP DO SCHEMA CONCLUÍDO! 🎉       ║"
log_success "╚════════════════════════════════════════╝"
echo ""
echo "📦 Arquivo: ${BACKUP_DIR}.tar.gz"
echo "📊 Tamanho: ${size_display}"
echo ""
echo "📋 Próximos passos:"
echo "  1. Copie este arquivo para local seguro"
echo "  2. Para restaurar: extraia e leia o README.md"
echo "  3. Execute o script RECREATE.sh"
echo ""
echo "⚠️  GUARDE ESTE BACKUP COM CUIDADO!"
echo "   Ele contém TODA a estrutura para recriar o ambiente."
echo ""
