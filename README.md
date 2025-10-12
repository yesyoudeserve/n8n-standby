# N8N Backup & Restore System v2.0

Sistema profissional de backup e restauração para ambientes N8N com EasyPanel, incluindo recuperação automática de desastre.

## 🚀 **Novidades da v2.0**

- ✅ **Script Principal Unificado**: `./n8n-backup.sh` detecta automaticamente o modo
- 🔐 **Criptografia de Ponta a Ponta**: Dados sensíveis criptografados com AES-256
- 🔄 **Recuperação de Desastre**: 1 comando para recriar tudo em nova VM
- 📢 **Monitoramento Discord**: Alertas automáticos via webhook
- 🛡️ **Verificação de Integridade**: Hashes SHA256 para validar backups
- 🤖 **Setup Automático**: Instalação completa com 1 comando

## 📋 **Instalação Rápida**

### Para VM Existente (Produção)
```bash
# 1. Bootstrap completo (baixa + instala + configura)
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh | bash

# 2. Sistema detecta credenciais automaticamente e pede apenas o que falta
# 3. Primeiro backup automático
./n8n-backup.sh backup
```

### Para Nova VM (Recuperação)
```bash
# 1. Bootstrap completo (baixa + instala + configura)
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh | bash

# 2. Sistema baixa configuração criptografada do cloud automaticamente
# 3. Pede apenas a senha mestra para descriptografar
# 4. Recuperação completa automática
./n8n-backup.sh recovery
```

### ⚠️ **IMPORTANTE: URLs Corretas**
Certifique-se de usar a branch **main** (não master):
- ✅ `https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh`
- ❌ `https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/master/bootstrap.sh`

## 🎯 **Como Usar**

### Modo Automático (Recomendado)
```bash
# O sistema detecta automaticamente o que fazer
./n8n-backup.sh
```

### Modos Específicos
```bash
# Backup manual
./n8n-backup.sh backup

# Restauração interativa
./n8n-backup.sh restore

# Status do sistema
./n8n-backup.sh status

# Recuperação de desastre (nova VM)
./n8n-backup.sh recovery
```

## 🔧 **Configuração**

### Arquivo `config.env`

```bash
# === CONFIGURAÇÕES DO N8N ===
N8N_POSTGRES_HOST="n8n_postgres"
N8N_POSTGRES_PASSWORD="ALTERAR_COM_SUA_SENHA_POSTGRES_REAL"
N8N_ENCRYPTION_KEY="ALTERAR_COM_SUA_CHAVE_ENCRYPTION_REAL"

# === ORACLE OBJECT STORAGE ===
ORACLE_ENABLED=true
ORACLE_NAMESPACE="seu-namespace"
ORACLE_BUCKET="n8n-backups"

# === BACKBLAZE B2 ===
B2_ENABLED=true
B2_BUCKET="n8n-backups-offsite"

# === SEGURANÇA ===
BACKUP_MASTER_PASSWORD="SENHA_MESTRA_FORTE_AQUI"
ENCRYPT_SENSITIVE_DATA=true
VERIFY_BACKUP_INTEGRITY=true

# === MONITORAMENTO ===
NOTIFY_WEBHOOK="https://discord.com/api/webhooks/..."
ENABLE_HEALTH_CHECKS=true
```

### Configuração do Rclone

```bash
# Configurar Oracle
rclone config

# Configurar B2
rclone config
```

## 🔐 **Segurança**

### Criptografia
- **Chaves simétricas**: Mesma chave para backup/restore
- **Armazenamento**: Chaves criptografadas no cloud storage
- **AES-256**: Padrão militar para dados sensíveis

### Dados Protegidos
- ✅ **N8N_ENCRYPTION_KEY** - Chave de criptografia do N8N
- ✅ **N8N_POSTGRES_PASSWORD** - Senha do banco PostgreSQL
- ✅ **ORACLE_NAMESPACE** - Namespace Oracle
- ✅ **ORACLE_COMPARTMENT_ID** - Compartment ID Oracle
- ✅ **B2_ACCOUNT_ID** - Account ID Backblaze
- ✅ **B2_APPLICATION_KEY** - Application Key Backblaze
- ✅ **config.env completo** - Todas as configurações
- ✅ Credenciais de bancos e APIs
- ✅ Dados pessoais e tokens

## 📊 **Monitoramento**

### Health Checks Automáticos
- Status dos containers N8N
- Conectividade PostgreSQL
- Espaço em disco
- Último backup
- Integridade dos storages

### Alertas Discord
- ✅ Backups bem-sucedidos
- 🚨 Falhas de backup
- ⚠️ Avisos de recursos
- 🔧 Health checks

## 🔄 **Recuperação de Desastre**

### 📍 **Onde ficam os códigos?**

Os códigos ficam versionados em **repositório Git** (GitHub/GitLab/etc.). Em caso de desastre:

1. **Códigos**: Sempre disponíveis no repositório Git
2. **Configurações**: Backup no Oracle/B2 (criptografadas)
3. **Dados**: Backup no Oracle/B2 (criptografados)

### Cenário: Nova VM Vazia

```bash
# 1. Bootstrap (baixa códigos + instala)
curl -sSL https://raw.githubusercontent.com/seu-repo/n8n-backup/main/bootstrap.sh | bash

# 2. Configurar rclone (credenciais de acesso aos storages)
cp /caminho/para/rclone.conf ~/.config/rclone/rclone.conf

# 3. Recuperação completa automática
./n8n-backup.sh recovery
```

### O que a recuperação faz:
1. ✅ **Instala dependências** (Docker, PostgreSQL, etc.)
2. ✅ **Baixa backup mais recente** automaticamente do Oracle/B2
3. ✅ **Instala EasyPanel**
4. ✅ **Restaura schema completo** (containers, networks, volumes)
5. ✅ **Importa banco de dados** (workflows, credenciais, executions)
6. ✅ **Verifica serviços** (testa conectividade)
7. ✅ **Configura monitoramento** (alertas automáticos)

### 🛡️ **Segurança dos Backups**

- **Oracle/B2**: Storages confiáveis com redundância
- **Criptografia**: AES-256 para dados sensíveis
- **Chaves**: Armazenadas criptografadas no próprio storage
- **Hashes**: Verificação de integridade SHA256
- **Multi-storage**: Oracle (primário) + B2 (offsite)

## 📁 **Estrutura de Arquivos**

```
n8n-backup/
├── n8n-backup.sh           # Script principal
├── backup.sh               # Lógica de backup
├── restore.sh              # Restauração interativa
├── backup-easypanel-schema.sh  # Backup completo do schema (criptografado)
├── install.sh              # Instalador
├── bootstrap.sh            # Bootstrap para novas VMs
├── config.env              # Configurações (criptografadas no backup)
├── rclone.conf             # Config rclone
├── lib/
│   ├── logger.sh           # Sistema de logs
│   ├── security.sh         # Criptografia AES-256
│   ├── recovery.sh         # Recuperação de desastre
│   ├── monitoring.sh       # Alertas Discord
│   ├── menu.sh             # Menus interativos
│   └── postgres.sh         # Funções PostgreSQL
└── backups/local/          # Backups locais
```

### 🔐 **Arquivos Criptografados nos Backups**

```
backup.tar.gz/
├── config.env.enc              # ⚠️  CONFIGURAÇÕES CRIPTOGRAFADAS
├── encryption_key.txt.enc      # ⚠️  CHAVE N8N CRIPTOGRAFADA
├── postgres_password.txt.enc   # ⚠️  SENHA DB CRIPTOGRAFADA
├── easypanel_configs/
│   ├── n8n-main_env.json.enc   # ⚠️  VARS DE AMBIENTE CRIPTOGRAFADAS
│   └── easypanel_etc/
│       └── *.env.enc           # ⚠️  CONFIGS EASYPANEL CRIPTOGRAFADAS
└── n8n_dump.sql.gz            # ✅ Dados workflows (não sigilosos)
```

## 🎛️ **Funcionalidades**

### Backup Inteligente
- **Seletivo**: Apenas executions recentes (7 dias)
- **Completo**: Schema EasyPanel + PostgreSQL + configs
- **Verificado**: Integridade com hashes SHA256
- **Criptografado**: Dados sensíveis protegidos

### Restauração Granular
- **Workflow específico**
- **Credencial específica**
- **Banco completo**
- **Schema EasyPanel**

### Storages Suportados
- **Oracle Object Storage** (primário)
- **Backblaze B2** (offsite)
- **Local** (temporário)

## 📈 **Retenção**

- **Local**: 2 dias
- **Oracle**: 7 dias
- **B2**: 30 dias
- **Limpeza automática**

## 🚨 **Alertas e Troubleshooting**

### Problemas Comuns

#### ❌ "rclone: comando não encontrado"
```bash
sudo apt install rclone
```

#### ❌ "Falha na criptografia"
```bash
# Verificar senha mestra
grep BACKUP_MASTER_PASSWORD config.env
```

#### ❌ "Backup corrompido"
```bash
# Verificar hash
sha256sum -c backup.tar.gz.sha256
```

#### ❌ "Nenhum backup encontrado"
```bash
# Verificar storages
rclone lsd oracle:
rclone lsd b2:
```

## 📞 **Suporte**

### Logs Importantes
```bash
# Log principal
tail -f /opt/n8n-backup/logs/backup.log

# Log de monitoramento
tail -f /opt/n8n-backup/logs/monitoring.log

# Health checks
/opt/n8n-backup/health-check.sh
```

### Status do Sistema
```bash
./n8n-backup.sh status
```

## 🤝 **Contribuição**

1. Fork o projeto
2. Crie uma branch (`git checkout -b feature/nova-feature`)
3. Commit suas mudanças (`git commit -am 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/nova-feature`)
5. Abra um Pull Request

## 📄 **Licença**

Este projeto está sob a licença MIT. Veja o arquivo `LICENSE` para detalhes.

---

**Desenvolvido com ❤️ para a comunidade N8N**
