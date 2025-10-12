#!/bin/bash
# ============================================
# Script Interativo de Restauração N8N
# Arquivo: /opt/n8n-backup/restore.sh
# ============================================

set -euo pipefail

# Diretório base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Carregar configurações e bibliotecas
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/menu.sh"
source "${SCRIPT_DIR}/lib/postgres.sh"

# Variáveis globais
SELECTED_BACKUP=""
TEMP_RESTORE_DIR=""
POSTGRES_CONTAINER=$(docker ps --filter "name=n8n_postgres" --format "{{.Names}}" | head -1)

# Função principal
main() {
    show_banner
    log_info "Sistema de Restauração N8N"
    echo ""
    
    # Criar diretório temporário
    TEMP_RESTORE_DIR=$(mktemp -d)
    trap cleanup EXIT
    
    # Loop do menu principal
    while true; do
        choice=$(show_main_menu)
        
        case $choice in
            1) list_backups_menu ;;
            2) restore_workflow_menu ;;
            3) restore_credential_menu ;;
            4) restore_full_database_menu ;;
            5) restore_easypanel_configs_menu ;;
            6) view_backup_details_menu ;;
            7) test_backup_integrity_menu ;;
            8) break ;;
            *) break ;;
        esac
    done
    
    log_info "Saindo..."
    cleanup
}

# Limpar arquivos temporários
cleanup() {
    if [ -n "$TEMP_RESTORE_DIR" ] && [ -d "$TEMP_RESTORE_DIR" ]; then
        rm -rf "$TEMP_RESTORE_DIR"
    fi
}

# Menu: Listar backups disponíveis
list_backups_menu() {
    local source_choice=$(select_backup_source)
    
    case $source_choice in
        1) list_backups_from_local ;;
        2) list_backups_from_oracle ;;
        3) list_backups_from_b2 ;;
        4) return ;;
    esac
    
    dialog --msgbox "Pressione ENTER para voltar ao menu" 7 40
}

# Listar backups locais
list_backups_from_local() {
    local backups=()
    local info=""
    
    while IFS= read -r backup; do
        local basename=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d'.' -f1)
        info="${info}\n${basename}\n  Tamanho: ${size}\n  Data: ${date}\n"
    done < <(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f | sort -r | head -10)
    
    if [ -z "$info" ]; then
        dialog --msgbox "Nenhum backup local encontrado" 7 40
    else
        dialog --title "Backups Locais" --msgbox "Últimos 10 backups:\n${info}" 20 70
    fi
}

# Listar backups Oracle
list_backups_from_oracle() {
    if [ "$ORACLE_ENABLED" != true ]; then
        dialog --msgbox "Oracle Object Storage não está habilitado" 7 50
        return
    fi
    
    log_info "Buscando backups no Oracle..."
    local backups=$(rclone lsl "oracle:${ORACLE_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | tail -10)
    
    if [ -z "$backups" ]; then
        dialog --msgbox "Nenhum backup encontrado no Oracle" 7 40
    else
        dialog --title "Backups no Oracle" --msgbox "${backups}" 20 80
    fi
}

# Listar backups B2
list_backups_from_b2() {
    if [ "$B2_ENABLED" != true ]; then
        dialog --msgbox "Backblaze B2 não está habilitado" 7 50
        return
    fi
    
    log_info "Buscando backups no B2..."
    local backups=$(rclone lsl "b2:${B2_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | tail -10)
    
    if [ -z "$backups" ]; then
        dialog --msgbox "Nenhum backup encontrado no B2" 7 40
    else
        dialog --title "Backups no B2 (Offsite)" --msgbox "${backups}" 20 80
    fi
}

# Menu: Restaurar workflow específico
restore_workflow_menu() {
    # Selecionar fonte
    local source_choice=$(select_backup_source)
    [ -z "$source_choice" ] && return
    
    # Selecionar backup
    local backup_file=$(select_backup_file "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Baixar se necessário
    backup_file=$(download_backup_if_needed "$backup_file" "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Listar workflows do backup
    local workflow_choice=$(list_workflows_from_backup "$backup_file")
    [ -z "$workflow_choice" ] && return
    
    # Extrair nome do workflow
    local workflow_name=$(extract_workflow_name "$backup_file" "$workflow_choice")
    
    # Confirmar restauração
    if confirm_restore "Workflow: ${workflow_name}" "$(basename $backup_file)"; then
        restore_workflow "$backup_file" "$workflow_name"
        dialog --msgbox "Workflow restaurado com sucesso!" 7 40
    else
        dialog --msgbox "Restauração cancelada" 7 40
    fi
}

# Menu: Restaurar credencial específica
restore_credential_menu() {
    # Selecionar fonte
    local source_choice=$(select_backup_source)
    [ -z "$source_choice" ] && return
    
    # Selecionar backup
    local backup_file=$(select_backup_file "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Baixar se necessário
    backup_file=$(download_backup_if_needed "$backup_file" "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Listar credenciais do backup
    local cred_choice=$(list_credentials_from_backup "$backup_file")
    [ -z "$cred_choice" ] && return
    
    # Extrair nome da credencial
    local cred_name=$(extract_credential_name "$backup_file" "$cred_choice")
    
    # Confirmar restauração
    if confirm_restore "Credencial: ${cred_name}" "$(basename $backup_file)"; then
        restore_credential "$backup_file" "$cred_name"
        dialog --msgbox "Credencial restaurada com sucesso!" 7 40
    else
        dialog --msgbox "Restauração cancelada" 7 40
    fi
}

# Menu: Restaurar banco completo
restore_full_database_menu() {
    # Aviso de perigo
    dialog --title "⚠️  ATENÇÃO" --yesno \
        "Você está prestes a RESTAURAR O BANCO COMPLETO.\n\nIsso irá SOBRESCREVER todos os workflows, credenciais e executions atuais.\n\nEsta ação não pode ser desfeita.\n\nTem CERTEZA ABSOLUTA?" 12 60
    
    if [ $? -ne 0 ]; then
        dialog --msgbox "Operação cancelada" 7 40
        return
    fi
    
    # Selecionar fonte
    local source_choice=$(select_backup_source)
    [ -z "$source_choice" ] && return
    
    # Selecionar backup
    local backup_file=$(select_backup_file "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Baixar se necessário
    backup_file=$(download_backup_if_needed "$backup_file" "$source_choice")
    [ -z "$backup_file" ] && return
    
    # Confirmação final
    dialog --title "⚠️  ÚLTIMA CONFIRMAÇÃO" --yesno \
        "Arquivo: $(basename $backup_file)\n\nEsta é sua ÚLTIMA CHANCE de cancelar.\n\nDeseja REALMENTE restaurar o banco completo?" 10 60
    
    if [ $? -eq 0 ]; then
        # Extrair dump SQL
        log_info "Extraindo backup..."
        tar -xzf "$backup_file" -C "$TEMP_RESTORE_DIR"
        
        local dump_file=$(find "$TEMP_RESTORE_DIR" -name "n8n_dump.sql.gz" | head -1)
        
        if [ -z "$dump_file" ]; then
            dialog --msgbox "Erro: dump SQL não encontrado no backup" 7 50
            return
        fi
        
        # Restaurar via docker exec
        (
            echo "10" ; sleep 1
            echo "30" ; log_info "Conectando ao banco..."
            echo "50" ; log_info "Restaurando dados..."
            gunzip < "$dump_file" | docker exec -i "${POSTGRES_CONTAINER}" psql \
                -U "${N8N_POSTGRES_USER}" \
                -d "${N8N_POSTGRES_DB}" \
                > /dev/null 2>&1
            echo "100" ; sleep 1
        ) | dialog --title "Restaurando Banco" --gauge "Restaurando banco de dados..." 7 70 0
        
        dialog --msgbox "✓ Banco restaurado com sucesso!\n\nReinicie o N8N para aplicar as mudanças:\ndocker restart n8n-main" 10 50
    else
        dialog --msgbox "Restauração cancelada" 7 40
    fi
}

# Menu: Restaurar configs EasyPanel
restore_easypanel_configs_menu() {
    dialog --msgbox "Funcionalidade em desenvolvimento.\n\nPor enquanto, restaure manualmente os arquivos da pasta easypanel_configs do backup." 10 50
}

# Menu: Ver detalhes de um backup
view_backup_details_menu() {
    local source_choice=$(select_backup_source)
    [ -z "$source_choice" ] && return
    
    local backup_file=$(select_backup_file "$source_choice")
    [ -z "$backup_file" ] && return
    
    backup_file=$(download_backup_if_needed "$backup_file" "$source_choice")
    [ -z "$backup_file" ] && return
    
    show_backup_details "$backup_file"
}

# Menu: Testar integridade
test_backup_integrity_menu() {
    local source_choice=$(select_backup_source)
    [ -z "$source_choice" ] && return
    
    local backup_file=$(select_backup_file "$source_choice")
    [ -z "$backup_file" ] && return
    
    backup_file=$(download_backup_if_needed "$backup_file" "$source_choice")
    [ -z "$backup_file" ] && return
    
    log_info "Testando integridade do backup..."
    
    if tar -tzf "$backup_file" > /dev/null 2>&1; then
        dialog --msgbox "✓ Backup íntegro!\n\nO arquivo não está corrompido." 8 40
    else
        dialog --msgbox "✗ Backup corrompido!\n\nO arquivo está danificado." 8 40
    fi
}

# Selecionar arquivo de backup
select_backup_file() {
    local source=$1
    local backups=()
    local count=1
    
    case $source in
        1) # Local
            while IFS= read -r backup; do
                local basename=$(basename "$backup")
                local size=$(du -h "$backup" | cut -f1)
                backups+=("$count" "${basename} (${size})")
                ((count++))
            done < <(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f | sort -r)
            ;;
        2) # Oracle
            while IFS= read -r line; do
                local filename=$(echo "$line" | awk '{print $NF}')
                local size=$(echo "$line" | awk '{print $1}')
                backups+=("$count" "${filename} (${size})")
                ((count++))
            done < <(rclone lsl "oracle:${ORACLE_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | sort -r)
            ;;
        3) # B2
            while IFS= read -r line; do
                local filename=$(echo "$line" | awk '{print $NF}')
                local size=$(echo "$line" | awk '{print $1}')
                backups+=("$count" "${filename} (${size})")
                ((count++))
            done < <(rclone lsl "b2:${B2_BUCKET}/" 2>/dev/null | grep "n8n_backup_" | sort -r)
            ;;
    esac
    
    if [ ${#backups[@]} -eq 0 ]; then
        dialog --msgbox "Nenhum backup encontrado" 7 40
        return 1
    fi
    
    local selection=$(dialog --clear --backtitle "Selecionar Backup" \
           --title "Escolha um Backup" \
           --menu "Backups disponíveis:" 20 70 15 \
           "${backups[@]}" 2>&1 >/dev/tty)
    
    if [ -n "$selection" ]; then
        echo "${backups[$((selection*2-1))]}" | awk '{print $1}'
    fi
}

# Baixar backup se não for local
download_backup_if_needed() {
    local filename=$1
    local source=$2
    
    case $source in
        1) # Já é local
            echo "${BACKUP_LOCAL_DIR}/${filename}"
            ;;
        2) # Oracle
            local local_path="${TEMP_RESTORE_DIR}/${filename}"
            log_info "Baixando backup do Oracle..."
            rclone copy "oracle:${ORACLE_BUCKET}/${filename}" "$TEMP_RESTORE_DIR/" --progress 2>&1 | \
                dialog --title "Download" --programbox "Baixando de Oracle..." 20 70
            echo "$local_path"
            ;;
        3) # B2
            local local_path="${TEMP_RESTORE_DIR}/${filename}"
            log_info "Baixando backup do B2..."
            rclone copy "b2:${B2_BUCKET}/${filename}" "$TEMP_RESTORE_DIR/" --progress 2>&1 | \
                dialog --title "Download" --programbox "Baixando de B2..." 20 70
            echo "$local_path"
            ;;
    esac
}

# Extrair nome do workflow do backup
extract_workflow_name() {
    local backup_file=$1
    local workflow_num=$2
    
    tar -xzf "$backup_file" -C "$TEMP_RESTORE_DIR"
    local dump=$(find "$TEMP_RESTORE_DIR" -name "n8n_dump.sql.gz" | head -1)
    gunzip < "$dump" | grep "INSERT INTO public.workflow_entity" | \
        sed -n "${workflow_num}p" | grep -oP "VALUES \(\d+, '\K[^']+" || echo "workflow_${workflow_num}"
}

# Extrair nome da credencial do backup
extract_credential_name() {
    local backup_file=$1
    local cred_num=$2
    
    tar -xzf "$backup_file" -C "$TEMP_RESTORE_DIR"
    local dump=$(find "$TEMP_RESTORE_DIR" -name "n8n_dump.sql.gz" | head -1)
    gunzip < "$dump" | grep "INSERT INTO public.credentials_entity" | \
        sed -n "${cred_num}p" | grep -oP "VALUES \(\d+, '\K[^']+" || echo "credential_${cred_num}"
}

# Executar
main "$@"
