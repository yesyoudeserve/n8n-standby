# ============================================
# Debug Supabase - Teste Independente (PowerShell)
# Arquivo: debug-supabase.ps1
# ============================================

Write-Host "🔍 Debug Supabase - Teste das Credenciais Salvas" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# URLs e secrets
$SUPABASE_URL = "https://jpxctcxpxmevwiyaxkqu.supabase.co/functions/v1/backup-metadata"
$BACKUP_SECRET = "xt6F2!iRMul*y9"

# Função para mascarar strings
function Mask-String {
    param([string]$str)
    $len = $str.Length
    if ($len -le 8) {
        return "****"
    } else {
        return $str.Substring(0,4) + "****" + $str.Substring($len-4,4)
    }
}

# Função para calcular SHA256
function Get-SHA256 {
    param([string]$inputString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputString)
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace("-", "").ToLower()
}

# Pedir senha mestra
$MASTER_PASSWORD = Read-Host "🔑 Digite sua senha mestra" -AsSecureString
$MASTER_PASSWORD_TEXT = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($MASTER_PASSWORD))

if ([string]::IsNullOrEmpty($MASTER_PASSWORD_TEXT)) {
    Write-Host "❌ Senha não pode ser vazia!" -ForegroundColor Red
    exit 1
}

# Calcular hash
Write-Host "🔢 Calculando hash da senha..." -ForegroundColor Yellow
$BACKUP_KEY_HASH = Get-SHA256 $MASTER_PASSWORD_TEXT
Write-Host "Hash: $($BACKUP_KEY_HASH.Substring(0,16))..." -ForegroundColor Gray

# Fazer requisição GET
Write-Host "" -ForegroundColor White
Write-Host "📡 Fazendo requisição GET para Supabase..." -ForegroundColor Yellow

$jsonBody = @{
    action = "get"
    backupKeyHash = $BACKUP_KEY_HASH
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $SUPABASE_URL -Method POST -Body $jsonBody -ContentType "application/json" -Headers @{
        "Authorization" = "Bearer $BACKUP_SECRET"
    }

    Write-Host "Resposta bruta:" -ForegroundColor Gray
    $response | ConvertTo-Json | Write-Host

    # Verificar se tem dados
    if ($response.storageType) {
        Write-Host "" -ForegroundColor White
        Write-Host "✅ Dados encontrados no Supabase!" -ForegroundColor Green

        $STORAGE_TYPE = $response.storageType
        $STORAGE_CONFIG = $response.storageConfig

        Write-Host "Tipo: $STORAGE_TYPE" -ForegroundColor Gray
        Write-Host "Config length: $($STORAGE_CONFIG.Length)" -ForegroundColor Gray

        if ($STORAGE_TYPE -eq "encrypted" -and -not [string]::IsNullOrEmpty($STORAGE_CONFIG)) {
            Write-Host "" -ForegroundColor White
            Write-Host "🔓 Descriptografando dados..." -ForegroundColor Yellow

            try {
                # Decodificar base64
                $decodedBytes = [Convert]::FromBase64String($STORAGE_CONFIG)

                # Descriptografar AES-256-CBC com PBKDF2
                $aes = [System.Security.Cryptography.Aes]::Create()
                $aes.KeySize = 256
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

                # Derivar chave usando PBKDF2 (igual ao OpenSSL)
                $pbkdf2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($MASTER_PASSWORD_TEXT, [System.Text.Encoding]::UTF8.GetBytes("Salted__"), 10000)
                $aes.Key = $pbkdf2.GetBytes(32)  # 256 bits
                $aes.IV = $pbkdf2.GetBytes(16)   # 128 bits (IV)

                $decryptor = $aes.CreateDecryptor()
                $decryptedBytes = $decryptor.TransformFinalBlock($decodedBytes, 16, $decodedBytes.Length - 16)  # Skip salt
                $DECRYPTED_DATA = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)

                Write-Host "✅ Descriptografia bem-sucedida!" -ForegroundColor Green
                Write-Host "" -ForegroundColor White
                Write-Host "🔑 Credenciais descriptografadas:" -ForegroundColor Cyan
                Write-Host "================================" -ForegroundColor Cyan

                # Parsear as variáveis (usando regex simples)
                $lines = $DECRYPTED_DATA -split "`n"
                $variables = @{}

                foreach ($line in $lines) {
                    if ($line -match '^(\w+)="(.+)"$') {
                        $variables[$matches[1]] = $matches[2]
                    }
                }

                # Mostrar credenciais mascaradas
                Write-Host "ORACLE_CONFIG_BUCKET: $($variables['ORACLE_CONFIG_BUCKET'] ?? '<não definido>')" -ForegroundColor White
                Write-Host "ORACLE_NAMESPACE: $($variables['ORACLE_NAMESPACE'] ?? '<não definido>')" -ForegroundColor White
                Write-Host "ORACLE_REGION: $($variables['ORACLE_REGION'] ?? '<não definido>')" -ForegroundColor White
                Write-Host "ORACLE_ACCESS_KEY: $(Mask-String $variables['ORACLE_ACCESS_KEY'])" -ForegroundColor White
                Write-Host "ORACLE_SECRET_KEY: $(Mask-String $variables['ORACLE_SECRET_KEY'])" -ForegroundColor White
                Write-Host "" -ForegroundColor White
                Write-Host "B2_CONFIG_BUCKET: $($variables['B2_CONFIG_BUCKET'] ?? '<não definido>')" -ForegroundColor White
                Write-Host "B2_ACCOUNT_ID: $(Mask-String $variables['B2_ACCOUNT_ID'])" -ForegroundColor White
                Write-Host "B2_APPLICATION_KEY: $(Mask-String $variables['B2_APPLICATION_KEY'])" -ForegroundColor White
                Write-Host "B2_USE_SEPARATE_KEYS: $($variables['B2_USE_SEPARATE_KEYS'] ?? '<não definido>')" -ForegroundColor White
                Write-Host "B2_DATA_KEY: $(Mask-String $variables['B2_DATA_KEY'])" -ForegroundColor White
                Write-Host "B2_CONFIG_KEY: $(Mask-String $variables['B2_CONFIG_KEY'])" -ForegroundColor White

                Write-Host "" -ForegroundColor White
                Write-Host "🎯 Teste as credenciais no seu ambiente Linux!" -ForegroundColor Green
                Write-Host "Copie estes valores e veja se funcionam no rclone." -ForegroundColor Green

            } catch {
                Write-Host "❌ Falha na descriptografia!" -ForegroundColor Red
                Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Possíveis causas:" -ForegroundColor Yellow
                Write-Host "- Senha incorreta" -ForegroundColor Yellow
                Write-Host "- Dados corrompidos" -ForegroundColor Yellow
            }
        } else {
            Write-Host "❌ Formato de dados inválido" -ForegroundColor Red
        }

    } else {
        Write-Host "" -ForegroundColor White
        Write-Host "❌ Nenhum dado encontrado no Supabase" -ForegroundColor Red
        Write-Host "Possíveis causas:" -ForegroundColor Yellow
        Write-Host "- Senha incorreta" -ForegroundColor Yellow
        Write-Host "- Nunca fez setup completo" -ForegroundColor Yellow
        Write-Host "- Dados foram perdidos" -ForegroundColor Yellow
    }

} catch {
    Write-Host "❌ Erro na requisição: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "" -ForegroundColor White
Write-Host "🏁 Debug concluído!" -ForegroundColor Green

# Limpar senha da memória
$MASTER_PASSWORD_TEXT = $null
[GC]::Collect()
