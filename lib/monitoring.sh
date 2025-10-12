#!/bin/bash
# ============================================
# Funções de Monitoramento e Alertas
# Arquivo: /opt/n8n-backup/lib/monitoring.sh
# ============================================

# Enviar alerta para Discord
send_discord_alert() {
    local message=$1
    local level=${2:-"info"}  # info, warning, error, success

    if [ -z "$NOTIFY_WEBHOOK" ]; then
        return 0
    fi

    # Definir cores por nível
    local color=""
    case $level in
        info) color="3447003" ;;      # Azul
        warning) color="16776960" ;;  # Amarelo
        error) color="15158332" ;;    # Vermelho
        success) color="3066993" ;;   # Verde
    esac

    # Criar payload JSON
    local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "N8N Backup Alert",
    "description": "$message",
    "color": $color,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "footer": {
      "text": "$(hostname)"
    }
  }]
}
EOF
)

    # Enviar para Discord
    curl -H "Content-Type: application/json" \
         -d "$payload" \
         "$NOTIFY_WEBHOOK" \
         --max-time 10 \
         --silent \
         --show-error || true
}

# Health check completo do sistema
perform_health_check() {
    local issues_found=0
    local report=""

    # Verificar containers N8N
    report="${report}🐳 **Containers N8N:**\n"
    local n8n_containers=$(docker ps --filter "name=n8n" --format "{{.Names}}" 2>/dev/null || echo "")

    if [ -z "$n8n_containers" ]; then
        report="${report}❌ Nenhum container N8N encontrado\n"
        issues_found=$((issues_found + 1))
    else
        echo "$n8n_containers" | while read container; do
            local status=$(docker inspect "$container" 2>/dev/null | jq -r '.[0].State.Status' 2>/dev/null || echo "unknown")
            if [ "$status" = "running" ]; then
                report="${report}✅ $container: $status\n"
            else
                report="${report}❌ $container: $status\n"
                issues_found=$((issues_found + 1))
            fi
        done
    fi

    # Verificar PostgreSQL
    report="${report}\n🐘 **PostgreSQL:**\n"
    if docker exec n8n_postgres psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
        report="${report}✅ PostgreSQL OK\n"
    else
        report="${report}❌ PostgreSQL falha\n"
        issues_found=$((issues_found + 1))
    fi

    # Verificar conectividade N8N
    report="${report}\n🌐 **N8N Web Interface:**\n"
    if curl -f --max-time 5 http://localhost:5678/healthz > /dev/null 2>&1; then
        report="${report}✅ N8N respondendo\n"
    else
        report="${report}❌ N8N não responde\n"
        issues_found=$((issues_found + 1))
    fi

    # Verificar espaço em disco
    report="${report}\n💾 **Espaço em Disco:**\n"
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        report="${report}❌ Disco ${disk_usage}% usado (crítico)\n"
        issues_found=$((issues_found + 1))
    elif [ "$disk_usage" -gt 80 ]; then
        report="${report}⚠️ Disco ${disk_usage}% usado (atenção)\n"
    else
        report="${report}✅ Disco ${disk_usage}% usado\n"
    fi

    # Verificar backups recentes
    report="${report}\n📦 **Último Backup:**\n"
    local last_backup=$(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "Nenhum")

    if [ "$last_backup" = "Nenhum" ]; then
        report="${report}❌ Nenhum backup encontrado\n"
        issues_found=$((issues_found + 1))
    else
        local backup_age_hours=$(( ($(date +%s) - $(stat -c %Y "${BACKUP_LOCAL_DIR}/${last_backup}" 2>/dev/null || echo 0)) / 3600 ))
        if [ $backup_age_hours -gt 48 ]; then
            report="${report}❌ Último backup há ${backup_age_hours}h ($last_backup)\n"
            issues_found=$((issues_found + 1))
        elif [ $backup_age_hours -gt 24 ]; then
            report="${report}⚠️ Último backup há ${backup_age_hours}h ($last_backup)\n"
        else
            report="${report}✅ Último backup há ${backup_age_hours}h ($last_backup)\n"
        fi
    fi

    # Verificar storages remotos
    report="${report}\n☁️ **Storages Remotos:**\n"
    if [ "$ORACLE_ENABLED" = true ]; then
        if rclone lsd oracle: > /dev/null 2>&1; then
            report="${report}✅ Oracle OK\n"
        else
            report="${report}❌ Oracle falha\n"
            issues_found=$((issues_found + 1))
        fi
    fi

    if [ "$B2_ENABLED" = true ]; then
        if rclone lsd b2: > /dev/null 2>&1; then
            report="${report}✅ B2 OK\n"
        else
            report="${report}❌ B2 falha\n"
            issues_found=$((issues_found + 1))
        fi
    fi

    # Enviar alerta se houver problemas
    if [ $issues_found -gt 0 ]; then
        send_discord_alert "**🚨 PROBLEMAS DETECTADOS**\n\n${report}" "error"
    elif [ "$NOTIFY_WEBHOOK" ]; then
        # Health check diário bem-sucedido
        send_discord_alert "**✅ Health Check OK**\n\nSistema funcionando normalmente.\n\n${report}" "success"
    fi

    # Salvar relatório local
    echo "$(date): Health check - Issues: $issues_found" >> "${LOG_FILE}.health"

    return $issues_found
}

# Verificar se backup foi executado recentemente
check_backup_schedule() {
    local max_age_hours=${1:-25}  # 25 horas por padrão

    local last_backup=$(find "${BACKUP_LOCAL_DIR}" -name "n8n_backup_*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f1 2>/dev/null || echo 0)

    local current_time=$(date +%s)
    local backup_age_hours=$(( (current_time - last_backup) / 3600 ))

    if [ $backup_age_hours -gt $max_age_hours ]; then
        send_discord_alert "⚠️ **Backup Atrasado**\n\nÚltimo backup há ${backup_age_hours} horas.\nVerifique o cron job: \`crontab -l\`" "warning"
        return 1
    fi

    return 0
}

# Monitorar uso de recursos
monitor_resources() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

    # Alertar se recursos críticos
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        send_discord_alert "🔥 **CPU Crítico**: ${cpu_usage}% de uso" "error"
    elif (( $(echo "$cpu_usage > 80" | bc -l) )); then
        send_discord_alert "⚠️ **CPU Alto**: ${cpu_usage}% de uso" "warning"
    fi

    if [ $mem_usage -gt 90 ]; then
        send_discord_alert "🔥 **Memória Crítica**: ${mem_usage}% de uso" "error"
    elif [ $mem_usage -gt 80 ]; then
        send_discord_alert "⚠️ **Memória Alta**: ${mem_usage}% de uso" "warning"
    fi
}

# Alertar sobre falha de backup
alert_backup_failure() {
    local error_message=$1

    send_discord_alert "❌ **FALHA NO BACKUP**\n\nErro: ${error_message}\n\nVerifique os logs: \`tail -f ${LOG_FILE}\`" "error"
}

# Alertar sobre sucesso de backup
alert_backup_success() {
    local backup_file=$1
    local backup_size=$2

    if [ "$NOTIFY_WEBHOOK" ]; then
        send_discord_alert "✅ **Backup Concluído**\n\nArquivo: ${backup_file}\nTamanho: ${backup_size}\n\nDestinos: $([ "$ORACLE_ENABLED" = true ] && echo "Oracle ") $([ "$B2_ENABLED" = true ] && echo "B2 ")" "success"
    fi
}

# Configurar monitoramento automático
setup_automatic_monitoring() {
    log_info "Configurando monitoramento automático..."

    # Health check periódico
    if [ "$ENABLE_HEALTH_CHECKS" = true ]; then
        local cron_job="*/${HEALTH_CHECK_INTERVAL} * * * * /opt/n8n-backup/lib/monitoring.sh health_check >> /opt/n8n-backup/logs/monitoring.log 2>&1"

        # Remover job existente se houver
        crontab -l 2>/dev/null | grep -v "monitoring.sh" | crontab -

        # Adicionar novo job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

        log_success "Health checks configurados (a cada ${HEALTH_CHECK_INTERVAL} minutos)"
    fi
}

# Executar health check (função principal)
health_check() {
    perform_health_check
    check_backup_schedule
    monitor_resources
}

# Função principal do script
main() {
    case "${1:-health_check}" in
        health_check)
            health_check
            ;;
        alert_failure)
            alert_backup_failure "$2"
            ;;
        alert_success)
            alert_backup_success "$2" "$3"
            ;;
        setup)
            setup_automatic_monitoring
            ;;
        *)
            echo "Uso: $0 {health_check|alert_failure|alert_success|setup}"
            exit 1
            ;;
    esac
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
