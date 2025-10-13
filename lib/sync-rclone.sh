#!/bin/bash
# ============================================
# Sincronizar rclone.conf para root
# Arquivo: /opt/n8n-backup/lib/sync-rclone.sh
# ============================================

# Carregar logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/logger.sh" 2>/dev/null || true

sync_rclone_to_root() {
    # Verificar se existe config do usuário
    if [ ! -f ~/.config/rclone/rclone.conf ]; then
        echo "Erro: ~/.config/rclone/rclone.conf não encontrado"
        return 1
    fi

    # Copiar para root
    sudo mkdir -p /root/.config/rclone
    sudo cp ~/.config/rclone/rclone.conf /root/.config/rclone/rclone.conf
    sudo chown root:root /root/.config/rclone/rclone.conf
    sudo chmod 600 /root/.config/rclone/rclone.conf

    echo "✓ Configuração rclone sincronizada para root"
}

# Executar
sync_rclone_to_root