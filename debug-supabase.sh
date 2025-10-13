#!/bin/bash
# ============================================
# Debug Supabase - Teste Independente
# Arquivo: debug-supabase.sh
# ============================================

echo "🔍 Debug Supabase - Teste das Credenciais Salvas"
echo "================================================"

# URLs e secrets
SUPABASE_URL="https://jpxctcxpxmevwiyaxkqu.supabase.co/functions/v1/backup-metadata"
BACKUP_SECRET="xt6F2!iRMul*y9"

# Função para mascarar strings
mask_string() {
    local str=$1
    local len=${#str}
    if [ $len -le 8 ]; then
        echo "****"
    else
        echo "${str:0:4}****${str: -4}"
    fi
}

# Pedir senha mestra
echo ""
echo "🔑 Digite sua senha mestra:"
read -s MASTER_PASSWORD
echo ""

if [ -z "$MASTER_PASSWORD" ]; then
    echo "❌ Senha não pode ser vazia!"
    exit 1
fi

# Calcular hash
echo "🔢 Calculando hash da senha..."
BACKUP_KEY_HASH=$(echo -n "$MASTER_PASSWORD" | sha256sum | awk '{print $1}')
echo "Hash: ${BACKUP_KEY_HASH:0:16}..."

# Fazer requisição GET
echo ""
echo "📡 Fazendo requisição GET para Supabase..."
RESPONSE=$(curl -s -X POST "$SUPABASE_URL" \
    -H "Authorization: Bearer $BACKUP_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"action\":\"get\",\"backupKeyHash\":\"$BACKUP_KEY_HASH\"}")

echo "Resposta bruta:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"

# Verificar se tem dados
if echo "$RESPONSE" | jq -e '.storageType' > /dev/null 2>&1; then
    echo ""
    echo "✅ Dados encontrados no Supabase!"

    STORAGE_TYPE=$(echo "$RESPONSE" | jq -r '.storageType')
    STORAGE_CONFIG=$(echo "$RESPONSE" | jq -r '.storageConfig')

    echo "Tipo: $STORAGE_TYPE"
    echo "Config length: ${#STORAGE_CONFIG}"

    if [ "$STORAGE_TYPE" = "encrypted" ] && [ -n "$STORAGE_CONFIG" ]; then
        echo ""
        echo "🔓 Descriptografando dados..."

        # Descriptografar
        DECRYPTED_DATA=$(echo "$STORAGE_CONFIG" | base64 -d | openssl enc -d -aes-256-cbc -salt -pbkdf2 \
            -pass pass:"$MASTER_PASSWORD" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$DECRYPTED_DATA" ]; then
            echo "✅ Descriptografia bem-sucedida!"
            echo ""
            echo "🔑 Credenciais descriptografadas:"
            echo "================================"

            # Parsear as variáveis (eval seguro)
            eval "$DECRYPTED_DATA" 2>/dev/null || echo "❌ Erro ao parsear variáveis"

            # Mostrar credenciais mascaradas
            echo "ORACLE_CONFIG_BUCKET: ${ORACLE_CONFIG_BUCKET:-<não definido>}"
            echo "ORACLE_NAMESPACE: ${ORACLE_NAMESPACE:-<não definido>}"
            echo "ORACLE_REGION: ${ORACLE_REGION:-<não definido>}"
            echo "ORACLE_ACCESS_KEY: $(mask_string "${ORACLE_ACCESS_KEY:-}")"
            echo "ORACLE_SECRET_KEY: $(mask_string "${ORACLE_SECRET_KEY:-}")"
            echo ""
            echo "B2_CONFIG_BUCKET: ${B2_CONFIG_BUCKET:-<não definido>}"
            echo "B2_ACCOUNT_ID: $(mask_string "${B2_ACCOUNT_ID:-}")"
            echo "B2_APPLICATION_KEY: $(mask_string "${B2_APPLICATION_KEY:-}")"
            echo "B2_USE_SEPARATE_KEYS: ${B2_USE_SEPARATE_KEYS:-<não definido>}"
            echo "B2_DATA_KEY: $(mask_string "${B2_DATA_KEY:-}")"
            echo "B2_CONFIG_KEY: $(mask_string "${B2_CONFIG_KEY:-}")"

            echo ""
            echo "🎯 Teste as credenciais no seu ambiente Linux!"
            echo "Copie estes valores e veja se funcionam no rclone."

        else
            echo "❌ Falha na descriptografia!"
            echo "Possíveis causas:"
            echo "- Senha incorreta"
            echo "- Dados corrompidos"
        fi
    else
        echo "❌ Formato de dados inválido"
    fi

else
    echo ""
    echo "❌ Nenhum dado encontrado no Supabase"
    echo "Possíveis causas:"
    echo "- Senha incorreta"
    echo "- Nunca fez setup completo"
    echo "- Dados foram perdidos"
fi

echo ""
echo "🏁 Debug concluído!"
