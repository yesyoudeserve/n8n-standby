#!/bin/bash
# ============================================
# Sistema de Menus Interativos
# Arquivo: /opt/n8n-backup/lib/menu.sh
# ============================================

# Menu principal de restauração
show_main_menu() {
    dialog --clear --backtitle "N8N Backup & Restore System" \
           --title "Menu Principal de Restauração" \
           --menu "Escolha uma opção:" 15 60 8 \
           1 "Listar Backups Disponíveis" \
           2 "Restaurar Workflow Específico" \
           3 "Restaurar Credencial Específica" \
           4 "Restaurar Banco Completo" \
           5 "Restaurar Configurações EasyPanel" \
           6 "Ver Detalhes de um Backup" \
           7 "Teste de Integridade de Backup" \
           8 "Sair" 2>&1 >/dev/tty
}

# Listar backups disponíveis
list_available_backups() {
    local source=$1  # "local", "oracle", "b2"
    
    log_info "Buscando backups disponíveis em ${source}..."
    
    case $source in
        local)
            list_local_backups
            ;;
        oracle)
            list_oracle_backups
            ;;
        b2)
            list_b2_backups
            ;;
        *)
            log_error "Fonte inválida: ${source}"
            return 1
            ;;
    esac
}

# Listar backups locais
list_local_backups() {
    local backups=()
    local count=1
    
    while IFS= read -r backup; do
        local basename=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(echo "$basename" | grep -oP '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}')
        backups+=("$count" "${date} (${size})")
        ((count++))
    done < <(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f | sort -r)
    
    if [ ${#backups[@]} -eq 0 ]; then
        dialog --msgbox "Nenhum backup local encontrado." 7 40
        return 1
    fi
    
    dialog --clear --backtitle "Backups Locais" \
           --title "Selecione um Backup" \
           --menu "Backups disponíveis:" 20 70 15 \
           "${backups[@]}" 2>&1 >/dev/tty
}

# Menu para selecionar fonte de backup
select_backup_source() {
    dialog --clear --backtitle "Seleção de Fonte" \
           --title "De onde restaurar?" \
           --menu "Escolha a fonte do backup:" 12 60 5 \
           1 "Backup Local (mais rápido)" \
           2 "Oracle Object Storage" \
           3 "Backblaze B2 (offsite)" \
           4 "Voltar" 2>&1 >/dev/tty
}

# Listar workflows de um backup
list_workflows_from_backup() {
    local backup_file=$1
    local temp_dir=$(mktemp -d)
    
    # Extrair dump SQL
    tar -xzf "$backup_file" -C "$temp_dir" "n8n_dump.sql" 2>/dev/null
    
    if [ ! -f "$temp_dir/n8n_dump.sql" ]; then
        log_error "Não foi possível extrair o dump SQL do backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extrair lista de workflows
    local workflows=$(grep -oP "INSERT INTO public.workflow_entity.*?VALUES \(\d+, '\K[^']+(?=')" "$temp_dir/n8n_dump.sql" | nl -w2 -s': ')
    
    rm -rf "$temp_dir"
    
    if [ -z "$workflows" ]; then
        dialog --msgbox "Nenhum workflow encontrado no backup." 7 40
        return 1
    fi
    
    # Converter para array para dialog
    local workflow_array=()
    while IFS= read -r line; do
        local num=$(echo "$line" | awk -F': ' '{print $1}' | xargs)
        local name=$(echo "$line" | awk -F': ' '{print $2}')
        workflow_array+=("$num" "$name")
    done <<< "$workflows"
    
    dialog --clear --backtitle "Workflows no Backup" \
           --title "Selecione um Workflow" \
           --menu "Workflows disponíveis:" 20 70 15 \
           "${workflow_array[@]}" 2>&1 >/dev/tty
}

# Listar credenciais de um backup
list_credentials_from_backup() {
    local backup_file=$1
    local temp_dir=$(mktemp -d)
    
    tar -xzf "$backup_file" -C "$temp_dir" "n8n_dump.sql" 2>/dev/null
    
    if [ ! -f "$temp_dir/n8n_dump.sql" ]; then
        log_error "Não foi possível extrair o dump SQL do backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extrair lista de credenciais (nome + tipo)
    local credentials=$(grep -oP "INSERT INTO public.credentials_entity.*?VALUES \(\d+, '\K[^']+(?=', '[^']+')" "$temp_dir/n8n_dump.sql" | nl -w2 -s': ')
    
    rm -rf "$temp_dir"
    
    if [ -z "$credentials" ]; then
        dialog --msgbox "Nenhuma credencial encontrada no backup." 7 40
        return 1
    fi
    
    local cred_array=()
    while IFS= read -r line; do
        local num=$(echo "$line" | awk -F': ' '{print $1}' | xargs)
        local name=$(echo "$line" | awk -F': ' '{print $2}')
        cred_array+=("$num" "$name")
    done <<< "$credentials"
    
    dialog --clear --backtitle "Credenciais no Backup" \
           --title "Selecione uma Credencial" \
           --menu "Credenciais disponíveis:" 20 70 15 \
           "${cred_array[@]}" 2>&1 >/dev/tty
}

# Mostrar detalhes de um backup
show_backup_details() {
    local backup_file=$1
    local temp_dir=$(mktemp -d)
    
    tar -tzf "$backup_file" > "$temp_dir/contents.txt"
    
    local size=$(du -h "$backup_file" | cut -f1)
    local date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
    local workflows_count=$(tar -xzf "$backup_file" -O "n8n_dump.sql" 2>/dev/null | grep -c "INSERT INTO public.workflow_entity")
    local creds_count=$(tar -xzf "$backup_file" -O "n8n_dump.sql" 2>/dev/null | grep -c "INSERT INTO public.credentials_entity")
    
    local details="
Arquivo: $(basename "$backup_file")
Tamanho: ${size}
Data: ${date}

Conteúdo:
- Workflows: ${workflows_count}
- Credenciais: ${creds_count}
- Configurações EasyPanel: $(grep -q "easypanel" "$temp_dir/contents.txt" && echo "Sim" || echo "Não")

Arquivos no backup:
$(cat "$temp_dir/contents.txt")
"
    
    dialog --title "Detalhes do Backup" --msgbox "$details" 25 80
    
    rm -rf "$temp_dir"
}

# Confirmação de restauração
confirm_restore() {
    local what=$1
    local from=$2
    
    dialog --clear --backtitle "Confirmação" \
           --title "⚠️  ATENÇÃO" \
           --yesno "Você está prestes a restaurar:\n\n${what}\n\nDe: ${from}\n\nEsta ação pode sobrescrever dados atuais.\n\nDeseja continuar?" 12 60
}

# Barra de progresso
show_progress_dialog() {
    local title=$1
    local message=$2
    
    dialog --title "$title" --gauge "$message" 7 70 0
}