# N8N Backup & Restore System v4.0

Sistema profissional de backup e restauração para ambientes N8N com EasyPanel, incluindo recuperação automática de desastre com redundância completa.

---

## 🚀 Instalação Rápida

### Para VM Existente (Produção)

```bash
# 1. Download e instalação
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh | bash
cd /opt/n8n-backup
sudo ./install.sh

# 2. Configuração interativa
./lib/setup.sh interactive

# 3. Primeiro backup
sudo ./n8n-backup.sh backup
```

### Para Nova VM (Recuperação)

```bash
# 1. Download e instalação
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/bootstrap.sh | bash
cd /opt/n8n-backup
sudo ./install.sh

# 2. Carregar configuração (apenas senha mestra)
./lib/setup.sh interactive

# 3. Recuperação completa
sudo ./n8n-backup.sh recovery
```

---

## 📋 Comandos Disponíveis

### 🔧 Gerenciamento de Configuração

```bash
# Configuração inicial ou carregar do cloud
./lib/setup.sh interactive

# Editar configurações existentes
./lib/setup.sh edit

# Apagar tudo e recomeçar (requer confirmação)
./lib/setup.sh delete
```

### 💾 Operações de Backup

```bash
# Fazer backup manual
sudo ./n8n-backup.sh backup

# Restaurar dados interativamente
sudo ./n8n-backup.sh restore

# Ver status do sistema
sudo ./n8n-backup.sh status

# Disaster recovery (nova VM)
sudo ./n8n-backup.sh recovery
```

### 📊 Monitoramento

```bash
# Ver logs em tempo real
tail -f /opt/n8n-backup/logs/backup.log

# Health check manual
/opt/n8n-backup/health-check.sh

# Status dos storages
rclone lsd oracle:
rclone lsd b2:
```

---

## 🎯 Novidades da v4.0

### ✨ Recursos Principais

- ✅ **Configuração Inteligente**: Detecta automaticamente credenciais N8N e PostgreSQL
- ✅ **Redundância Completa**: Salva em Oracle E B2 simultaneamente (offsite)
- ✅ **Modo Edit**: Edite qualquer configuração sem reconfigurar tudo
- ✅ **Modo Delete**: Apague tudo com segurança (senha + confirmação)
- ✅ **Criptografia AES-256**: Todos os dados sensíveis protegidos
- ✅ **Recovery Automático**: 1 comando para recriar tudo
- ✅ **Suporte a Chaves B2 Separadas**: Buckets com Application Keys diferentes

### 🔒 Segurança

- **Senha Mestra**: Protege todas as credenciais
- **Criptografia**: OpenSSL AES-256-CBC com PBKDF2
- **Redundância**: Config salva em 2 storages diferentes
- **Validação**: Hashes SHA256 para integridade
- **Metadados**: Supabase para localização automática

---

## 📦 Estrutura de Buckets

### Oracle Object Storage

```
oracle:n8n-backups/          ← Backups diários dos dados
├── n8n_backup_2025-01-15.tar.gz
├── n8n_backup_2025-01-14.tar.gz
└── ...

oracle:n8n-config/           ← Configurações criptografadas
└── config.enc
```

### Backblaze B2 (Offsite)

```
b2:n8n-backups-offsite/      ← Backups diários (cópia offsite)
├── n8n_backup_2025-01-15.tar.gz
├── n8n_backup_2025-01-14.tar.gz
└── ...

b2:n8n-config-offsite/       ← Configurações criptografadas (cópia)
└── config.enc
```

**Redundância Automática:**
- ✅ Dados: Oracle + B2
- ✅ Config: Oracle + B2
- ✅ Metadados: Supabase

---

## 🔐 Gerenciamento de Credenciais

### Primeira Configuração

```bash
./lib/setup.sh interactive
```

**O sistema pede:**
1. Senha mestra (cria nova)
2. N8N_ENCRYPTION_KEY (auto-detectada se possível)
3. N8N_POSTGRES_PASSWORD (auto-detectada se possível)
4. Oracle credentials (namespace, region, access key, secret key)
5. Oracle buckets (dados + config)
6. B2 credentials (account ID, application key)
7. B2 buckets (dados + config)
8. Discord webhook (opcional)

**Resultado:**
- ✅ Config salva em Oracle
- ✅ Config salva em B2
- ✅ Metadados no Supabase
- ✅ rclone.conf gerado automaticamente

### Carregar Configuração (VM Nova)

```bash
./lib/setup.sh interactive
```

**O sistema:**
1. Pede apenas senha mestra
2. Consulta Supabase (localização)
3. Baixa config do Oracle ou B2
4. Descriptografa automaticamente
5. Aplica tudo

**Pronto em segundos!**

### Editar Configuração

```bash
./lib/setup.sh edit
```

**Menu interativo:**
```
🔧 Modo de Edição
=================

Valores atuais:
1)  N8N_ENCRYPTION_KEY: n8nKey...xyz789
2)  N8N_POSTGRES_PASSWORD: post***
3)  ORACLE_NAMESPACE: axabc12345
4)  ORACLE_REGION: eu-madrid-1
5)  ORACLE_ACCESS_KEY: AKIA1234...
[... mais campos ...]

0)  Salvar alterações e sair

Qual campo deseja editar?
>
```

### Deletar Tudo

```bash
./lib/setup.sh delete
```

**Segurança:**
1. Pede senha mestra (validação)
2. Pede confirmação "DELETE"
3. Apaga de todos os lugares:
   - Local
   - Oracle
   - B2
   - Supabase
   - Reseta config.env

---

## 🎨 Configuração do config.env

```bash
# === N8N ===
N8N_POSTGRES_HOST="n8n_postgres"
N8N_POSTGRES_USER="postgres"
N8N_POSTGRES_DB="n8n"
N8N_POSTGRES_PASSWORD="sua-senha"        # Auto-detectada
N8N_ENCRYPTION_KEY="sua-chave"           # Auto-detectada

# === ORACLE (S3-compatible) ===
ORACLE_ENABLED=true
ORACLE_NAMESPACE="seu-namespace"
ORACLE_REGION="eu-madrid-1"
ORACLE_ACCESS_KEY="sua-access-key"
ORACLE_SECRET_KEY="sua-secret-key"
ORACLE_BUCKET="n8n-backups"              # Dados
ORACLE_CONFIG_BUCKET="n8n-config"        # Config

# === BACKBLAZE B2 ===
B2_ENABLED=true
B2_ACCOUNT_ID="seu-account-id"
B2_APPLICATION_KEY="sua-app-key"         # Master key
B2_USE_SEPARATE_KEYS=false               # Ou true se usar chaves separadas
B2_DATA_KEY=""                           # Se usar chaves separadas
B2_CONFIG_KEY=""                         # Se usar chaves separadas
B2_BUCKET="n8n-backups-offsite"          # Dados offsite
B2_CONFIG_BUCKET="n8n-config-offsite"    # Config offsite

# === RETENÇÃO ===
LOCAL_RETENTION_DAYS=2
REMOTE_RETENTION_DAILY=7
REMOTE_RETENTION_WEEKLY=30

# === SEGURANÇA ===
BACKUP_MASTER_PASSWORD="senha-mestra"
ENCRYPT_SENSITIVE_DATA=true
VERIFY_BACKUP_INTEGRITY=true

# === MONITORAMENTO ===
NOTIFY_WEBHOOK="https://discord.com/api/webhooks/..."
ENABLE_HEALTH_CHECKS=true
HEALTH_CHECK_INTERVAL=60
```

---

## 🔄 Fluxos de Uso

### Backup Diário Automático

```
3:00 AM (cron)
↓
sudo /opt/n8n-backup/backup.sh
↓
1. Backup PostgreSQL (seletivo - últimos 7 dias)
2. Backup configs EasyPanel
3. Backup N8N encryption key (seguro)
4. Criptografar dados sensíveis
5. Criar .tar.gz
6. Calcular hash SHA256
7. Upload para Oracle
8. Upload para B2 (offsite)
9. Limpeza de backups antigos
10. Alerta Discord (sucesso/falha)
```

### Disaster Recovery

```
Nova VM vazia
↓
curl bootstrap.sh | bash
↓
cd /opt/n8n-backup && sudo ./install.sh
↓
./lib/setup.sh interactive
(apenas senha mestra)
↓
sudo ./n8n-backup.sh recovery
↓
1. Instala dependências
2. Baixa backup mais recente (Oracle ou B2)
3. Instala EasyPanel
4. Restaura schema completo
5. Importa banco PostgreSQL
6. Verifica serviços
7. Configura monitoramento
↓
Sistema restaurado! 🎉
```

---

## 📊 Monitoramento e Alertas

### Discord Webhooks

```bash
# Alertas automáticos via Discord:
- ✅ Backup bem-sucedido (com tamanho)
- ❌ Falha no backup (com erro)
- ⚠️ Recursos críticos (CPU/RAM/Disco)
- 🔧 Health checks periódicos
```

### Health Checks

```bash
# Automático a cada 60 minutos
/opt/n8n-backup/lib/monitoring.sh health_check

# Verifica:
- Status containers N8N
- Conectividade PostgreSQL
- Espaço em disco
- Último backup
- Storages remotos
```

---

## 🛠️ Troubleshooting

### Config não carrega

```bash
# Verificar se config.enc existe nos storages
rclone ls oracle:n8n-config/
rclone ls b2:n8n-config-offsite/

# Tentar descriptografar manualmente
openssl enc -d -aes-256-cbc -salt -pbkdf2 \
  -pass pass:"SUA_SENHA_MESTRA" \
  -in /opt/n8n-backup/config.enc \
  -out /tmp/test.env
```

### rclone não conecta

```bash
# Testar conexão
rclone lsd oracle:
rclone lsd b2:

# Reconfigurar
rclone config

# Verificar config
cat ~/.config/rclone/rclone.conf
cat /root/.config/rclone/rclone.conf
```

### Backup falha

```bash
# Ver logs
tail -100 /opt/n8n-backup/logs/backup.log

# Testar conexão PostgreSQL
docker exec n8n_postgres psql -U postgres -d n8n -c "SELECT 1"

# Verificar espaço em disco
df -h /opt/n8n-backup/backups/local/
```

### Permissões Docker

```bash
# Adicionar usuário ao grupo docker
sudo usermod -aG docker $USER

# Re-login ou
newgrp docker
```

---

## 📁 Estrutura de Arquivos

```
/opt/n8n-backup/
├── n8n-backup.sh              # Script principal
├── backup.sh                  # Lógica de backup
├── restore.sh                 # Restauração interativa
├── backup-easypanel-schema.sh # Backup schema completo
├── install.sh                 # Instalador
├── bootstrap.sh               # Bootstrap remoto
├── config.env                 # Configurações
├── config.enc                 # Config criptografada
├── rclone.conf                # Template rclone
├── lib/
│   ├── logger.sh              # Sistema de logs
│   ├── menu.sh                # Menus interativos
│   ├── postgres.sh            # Funções PostgreSQL
│   ├── security.sh            # Criptografia
│   ├── recovery.sh            # Disaster recovery
│   ├── monitoring.sh          # Alertas Discord
│   ├── setup.sh               # Configuração
│   ├── upload.sh              # Upload cloud
│   ├── generate-rclone.sh     # Gera rclone.conf
│   └── sync-rclone.sh         # Sync para root
├── backups/local/             # Backups locais
└── logs/                      # Logs do sistema
```

---

## 🔒 Segurança e Compliance

### Dados Criptografados

- ✅ N8N_ENCRYPTION_KEY
- ✅ N8N_POSTGRES_PASSWORD
- ✅ Todas as credenciais Oracle/B2
- ✅ config.env completo
- ✅ Configs EasyPanel

### Não Criptografados

- ✅ Workflows (dados de produção)
- ✅ Executions history
- ✅ Schema do banco

### Algoritmos

- **Simétrico**: AES-256-CBC com PBKDF2
- **Hash**: SHA256
- **Salt**: Automático (OpenSSL)

---

## ⏰ Retenção de Backups

| Local | Retenção |
|-------|----------|
| **Local** | 2 dias |
| **Oracle** | 7 dias |
| **B2** | 7 dias |

**Limpeza automática** após cada backup.

---

## 🚨 Disaster Recovery Checklist

- [ ] Guardar senha mestra em local seguro
- [ ] Testar restore pelo menos 1x por mês
- [ ] Verificar que Oracle E B2 estão funcionando
- [ ] Confirmar que backups automáticos estão rodando
- [ ] Salvar arquivo rclone.conf em local seguro
- [ ] Documentar procedimentos específicos da empresa

---

## 🤝 Contribuindo

1. Fork o projeto
2. Crie uma branch (`git checkout -b feature/nova-feature`)
3. Commit suas mudanças (`git commit -am 'Adiciona nova feature'`)
4. Push para a branch (`git push origin feature/nova-feature`)
5. Abra um Pull Request

---

## 📄 Licença

MIT License - veja LICENSE para detalhes

---

## 📞 Suporte

- **GitHub Issues**: https://github.com/yesyoudeserve/n8n-backup/issues
- **Documentação**: Este README
- **Logs**: `/opt/n8n-backup/logs/backup.log`

---

**Desenvolvido com ❤️ para a comunidade N8N**

**Versão:** 4.0  
**Última atualização:** Janeiro 2025