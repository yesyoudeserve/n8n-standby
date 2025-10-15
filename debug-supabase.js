#!/usr/bin/env node

// ============================================
// Debug Supabase - Teste Independente (Node.js)
// Arquivo: debug-supabase.js
// ============================================

const crypto = require('crypto');
const https = require('https');
const readline = require('readline');

console.log('🔍 Debug Supabase - Teste das Credenciais Salvas');
console.log('================================================');

// URLs e secrets
const SUPABASE_URL = 'https://jpxctcxpxmevwiyaxkqu.supabase.co/functions/v1/backup-metadata';
const BACKUP_SECRET = 'xt6F2!iRMul*y9';

// Função para mascarar strings
function maskString(str) {
    if (!str || str.length <= 8) return '****';
    return str.substring(0, 4) + '****' + str.substring(str.length - 4);
}

// Função para calcular SHA256
function getSHA256(inputString) {
    return crypto.createHash('sha256').update(inputString).digest('hex');
}

// Função para fazer requisição HTTPS
function makeRequest(url, data) {
    return new Promise((resolve, reject) => {
        const postData = JSON.stringify(data);

        const options = {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${BACKUP_SECRET}`,
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData)
            }
        };

        const req = https.request(url, options, (res) => {
            let body = '';
            res.on('data', (chunk) => {
                body += chunk;
            });
            res.on('end', () => {
                try {
                    const response = JSON.parse(body);
                    resolve(response);
                } catch (e) {
                    reject(new Error(`Erro ao parsear resposta: ${body}`));
                }
            });
        });

        req.on('error', (err) => {
            reject(err);
        });

        req.write(postData);
        req.end();
    });
}

// Função para descriptografar AES-256-CBC com PBKDF2
function decryptAES(encryptedData, password) {
    try {
        // Decodificar base64
        const encryptedBuffer = Buffer.from(encryptedData, 'base64');

        // Derivar chave usando PBKDF2 (igual ao OpenSSL)
        const salt = encryptedBuffer.subarray(8, 16); // Salt starts after "Salted__"
        const keyAndIv = crypto.pbkdf2Sync(password, salt, 10000, 48, 'sha256');
        const key = keyAndIv.subarray(0, 32); // 256 bits
        const iv = keyAndIv.subarray(32, 48);  // 128 bits

        // Descriptografar
        const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
        const decrypted = Buffer.concat([
            decipher.update(encryptedBuffer.subarray(16)), // Skip salt
            decipher.final()
        ]);

        return decrypted.toString('utf8');
    } catch (error) {
        throw new Error(`Erro na descriptografia: ${error.message}`);
    }
}

// Interface para ler senha
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

rl.question('🔑 Digite sua senha mestra: ', async (password) => {
    rl.close();

    if (!password || password.trim() === '') {
        console.log('❌ Senha não pode ser vazia!');
        process.exit(1);
    }

    try {
        // Calcular hash
        console.log('🔢 Calculando hash da senha...');
        const backupKeyHash = getSHA256(password);
        console.log(`Hash: ${backupKeyHash.substring(0, 16)}...`);

        // Fazer requisição GET
        console.log('');
        console.log('📡 Fazendo requisição GET para Supabase...');

        const response = await makeRequest(SUPABASE_URL, {
            action: 'get',
            backupKeyHash: backupKeyHash
        });

        console.log('Resposta bruta:');
        console.log(JSON.stringify(response, null, 2));

        // Verificar se tem dados
        if (response.storageType) {
            console.log('');
            console.log('✅ Dados encontrados no Supabase!');

            const { storageType, storageConfig } = response;
            console.log(`Tipo: ${storageType}`);
            console.log(`Config length: ${storageConfig.length}`);

            if (storageType === 'encrypted' && storageConfig) {
                console.log('');
                console.log('🔓 Descriptografando dados...');

                try {
                    const decryptedData = decryptAES(storageConfig, password);

                    console.log('✅ Descriptografia bem-sucedida!');
                    console.log('');
                    console.log('🔑 Credenciais descriptografadas:');
                    console.log('================================');

                    // Parsear as variáveis
                    const variables = {};
                    const lines = decryptedData.split('\n');

                    lines.forEach(line => {
                        const match = line.match(/^(\w+)="(.+)"$/);
                        if (match) {
                            variables[match[1]] = match[2];
                        }
                    });

                    // Mostrar TODAS as credenciais (para debug)
                    console.log('⚠️  ATENÇÃO: Credenciais completas sendo exibidas para debug!');
                    console.log('');
                    console.log(`ORACLE_CONFIG_BUCKET: ${variables.ORACLE_CONFIG_BUCKET || '<não definido>'}`);
                    console.log(`ORACLE_NAMESPACE: ${variables.ORACLE_NAMESPACE || '<não definido>'}`);
                    console.log(`ORACLE_REGION: ${variables.ORACLE_REGION || '<não definido>'}`);
                    console.log(`ORACLE_ACCESS_KEY: ${variables.ORACLE_ACCESS_KEY || '<não definido>'}`);
                    console.log(`ORACLE_SECRET_KEY: ${variables.ORACLE_SECRET_KEY || '<não definido>'}`);
                    console.log('');
                    console.log(`B2_CONFIG_BUCKET: ${variables.B2_CONFIG_BUCKET || '<não definido>'}`);
                    console.log(`B2_ACCOUNT_ID: ${variables.B2_ACCOUNT_ID || '<não definido>'}`);
                    console.log(`B2_APPLICATION_KEY: ${variables.B2_APPLICATION_KEY || '<não definido>'}`);
                    console.log(`B2_USE_SEPARATE_KEYS: ${variables.B2_USE_SEPARATE_KEYS || '<não definido>'}`);
                    console.log(`B2_DATA_KEY: ${variables.B2_DATA_KEY || '<não definido>'}`);
                    console.log(`B2_CONFIG_KEY: ${variables.B2_CONFIG_KEY || '<não definido>'}`);

                    console.log('');
                    console.log('🎯 Teste as credenciais no seu ambiente Linux!');
                    console.log('Copie estes valores e veja se funcionam no rclone.');

                } catch (error) {
                    console.log('❌ Falha na descriptografia!');
                    console.log(`Erro: ${error.message}`);
                    console.log('Possíveis causas:');
                    console.log('- Senha incorreta');
                    console.log('- Dados corrompidos');
                }
            } else {
                console.log('❌ Formato de dados inválido');
            }

        } else {
            console.log('');
            console.log('❌ Nenhum dado encontrado no Supabase');
            console.log('Possíveis causas:');
            console.log('- Senha incorreta');
            console.log('- Nunca fez setup completo');
            console.log('- Dados foram perdidos');
        }

    } catch (error) {
        console.log(`❌ Erro: ${error.message}`);
    }

    console.log('');
    console.log('🏁 Debug concluído!');
});
