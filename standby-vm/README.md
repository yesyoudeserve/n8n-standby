# 🏗️ N8N Standby VM System

Sistema de VM Standby para alta disponibilidade do N8N com EasyPanel.

## 📋 Visão Geral

Este sistema implementa uma arquitetura de alta disponibilidade com:
- **VM Principal**: Sempre ligada, produção
- **VM Standby**: Desligada 99% do tempo, backup
- **Sincronização**: Dados sempre atualizados na nuvem

## 🏛️ Arquitetura

```
┌─────────────────────┐
│   VM PRINCIPAL      │
│   (SEMPRE LIGADA)   │
│                     │
│   • EasyPanel       │
│   • N8N (prod)      │
│   • PostgreSQL      │
│                     │
│   Backup automático  │
└──────────┬──────────┘
           │
           │ Upload automático
           ▼
┌──────────────────────┬─────────────────────┐
│   Oracle S3          │   Backblaze B2      │
│   (principal)        │   (offsite)         │
│                      │                     │
│   • postgres.sql.gz  │   • postgres.sql.gz │
│   • encryption.key   │   • encryption.key  │
│   • snapshots/       │   • snapshots/      │
└──────────────────────┴─────────────────────┘
           │
           │ Sync quando necessário
           ▼
┌─────────────────────┐
│   VM STANDBY        │
│   (DESLIGADA 99%)   │
│                     │
│   • EasyPanel       │
│   • N8N (parado)    │
│   • PostgreSQL      │
│                     │
│   Custo: ~$3/mês    │
└─────────────────────┘
```

## 🚀 Guia Completo de Uso

### 📋 Pré-requisitos

Antes de começar, você precisa de:

#### **Contas de Nuvem:**
- ✅ **Oracle Cloud** (gratuito) ou **Backblaze B2** (barato)
- ✅ **Credenciais de API** (Access Keys, Secret Keys)
- ✅ **Buckets criados** para armazenar backups

#### **VM Standby:**
- ✅ **Ubuntu 22.04+** (ou similar)
- ✅ **Acesso root/sudo**
- ✅ **Conexão internet**
- ✅ **4GB RAM mínimo** (recomendado 8GB+)

#### **VM Principal (Produção):**
- ✅ **N8N rodando** com EasyPanel
- ✅ **PostgreSQL** configurado
- ✅ **Sistema de backup** já funcionando

---

### 1. 🏗️ Configurar VM Standby (Uma Vez)

#### **Opção 1: Bootstrap Automático (Recomendado)**
```bash
# Baixar e configurar tudo automaticamente
curl -fsSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/standby-vm/bootstrap-standby.sh | bash

# Entrar no diretório dos arquivos
cd /opt/n8n-standby

# Executar configuração completa
sudo ./setup-standby.sh
```

#### **Opção 2: Instalação Manual**
```bash
# Clonar repositório
git clone https://github.com/yesyoudeserve/n8n-backup.git
cd n8n-backup/standby-vm

# Dar permissões de execução
chmod +x *.sh lib/*.sh

# Executar setup
sudo ./setup-standby.sh
```

---

### 2. 🔐 Configurar Credenciais

Após o setup, configure as credenciais:

#### **Menu Interativo (Recomendado)**
```bash
# Executar menu interativo
./setup-credentials.sh
```

O menu permite configurar:
- **Oracle Cloud** (namespace, region, access keys)
- **Backblaze B2** (account ID, application key)
- **PostgreSQL** (host, user, password)
- **Segurança** (senha mestre para criptografia)

#### **Configuração Manual**
```bash
# Copiar template
cp config.env.template config.env

# Editar arquivo
nano config.env
```

**Arquivo config.env:**
```bash
# Oracle Cloud
ORACLE_ENABLED=true
ORACLE_NAMESPACE="seu-namespace"
ORACLE_REGION="eu-madrid-1"
ORACLE_ACCESS_KEY="sua-access-key"
ORACLE_SECRET_KEY="sua-secret-key"
ORACLE_BUCKET="n8n-backups"

# Backblaze B2
B2_ENABLED=true
B2_ACCOUNT_ID="seu-account-id"
B2_APPLICATION_KEY="sua-app-key"
B2_BUCKET="n8n-backups"

# PostgreSQL
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"
POSTGRES_USER="n8n"
POSTGRES_PASSWORD="sua-senha-postgres"
POSTGRES_DB="n8n"

# Segurança
BACKUP_MASTER_PASSWORD="sua-senha-mestre-super-segura"
```

---

### 3. 🧪 Testar Configuração

```bash
# Testar todas as configurações
./sync-standby.sh --test

# Verificar logs
tail -f logs/backup.log
```

---

### 4. 💤 Desligar VM Standby

```bash
# Após testes bem-sucedidos
sudo shutdown -h now
```

**IMPORTANTE:** Mantenha a VM Standby DESLIGADA. Ligue apenas em emergência!

---

### 5. 🔄 Backup Automático na VM Principal

Na VM de produção, configure backup automático:

```bash
# Configurar cron para backup a cada 3h
echo "0 */3 * * * /opt/n8n-backup/backup.sh >> /opt/n8n-backup/logs/cron.log 2>&1" | sudo crontab -

# Verificar configuração
sudo crontab -l

# Testar backup manual
sudo ./backup.sh
```

---

### 6. 🚨 Ativação de Emergência

Quando precisar ativar a VM Standby:

```bash
# 1. Ligar VM Standby
# 2. Entrar no diretório
cd /opt/n8n-standby

# 3. Sincronizar dados mais recentes
sudo ./sync-standby.sh

# 4. Verificar se tudo funcionou
# - EasyPanel: http://IP-DA-VM:3000
# - N8N deve estar rodando

# 5. Redirecionar tráfego
# - DNS ou Load Balancer para IP da VM Standby
```

---

### 7. 🔙 Retorno à Normalidade

Após resolver problemas na VM principal:

```bash
# 1. Configurar VM Principal como nova Standby
git clone https://github.com/yesyoudeserve/n8n-backup.git
cd n8n-backup/standby-vm
sudo ./setup-standby.sh
./setup-credentials.sh

# 2. Retornar tráfego para VM Principal
# - Atualizar DNS/Load Balancer

# 3. Desligar VM Standby antiga
sudo shutdown -h now
```

## 📁 Estrutura de Arquivos

```
standby-vm/
├── setup-standby.sh      # Configuração inicial da VM Standby
├── sync-standby.sh       # Sincronização com dados da nuvem
├── backup-production.sh  # Script de backup para VM Principal
├── config.env.template   # Template de configuração
└── README.md            # Esta documentação
```

## ⚙️ Funcionalidades

### Setup Standby
- ✅ Instala dependências (Docker, Node.js, etc.)
- ✅ Libera portas necessárias
- ✅ Instala EasyPanel
- ✅ Configura firewall
- ✅ Prepara estrutura para sincronização

### Backup Produção
- ✅ Backup completo N8N + EasyPanel
- ✅ Upload para Oracle + B2
- ✅ Criptografia de dados sensíveis
- ✅ Backup automático a cada 3h

### Sync Standby
- ✅ Baixa dados mais recentes da nuvem
- ✅ Restaura banco PostgreSQL
- ✅ Sincroniza configurações
- ✅ Prepara para ativação

## 🔄 Fluxo de Ativação

### Situação Normal
```
VM Principal: ✅ Ativa (produção)
VM Standby:  ❌ Desligada (backup)
```

### Ativação de Emergência
```
1. Desligar VM Principal
2. Ligar VM Standby
3. Executar: ./sync-standby.sh
4. Redirecionar webhooks/DNS
5. VM Standby torna-se produção
```

### Retorno à Normalidade
```
1. Reparar/recriar VM Principal
2. Configurar como nova Standby
3. Executar: ./setup-standby.sh
4. Retornar webhooks/DNS
```

## 💰 Custos

- **VM Standby**: ~$3/mês (desligada)
- **Storage Nuvem**: ~$1/mês (Oracle + B2)
- **Total**: ~$4/mês para HA completa

## 🔒 Segurança

- ✅ Dados criptografados na nuvem
- ✅ Senha mestra para descriptografia
- ✅ Backup duplo (Oracle + B2)
- ✅ Logs de auditoria

## 📊 Monitoramento

- ✅ Health checks automáticos
- ✅ Alertas Discord
- ✅ Logs centralizados
- ✅ Status de sincronização

## 🚨 Disaster Recovery

1. **Falha na VM Principal**
   - Ligar VM Standby
   - Executar sync
   - Redirecionar tráfego

2. **Falha na Nuvem**
   - Usar backup local
   - Ativar VM Standby manualmente

3. **Falha Geral**
   - Usar backups offsite (B2)
   - Recriar infraestrutura do zero

## 📝 Pré-requisitos

- Ubuntu 22.04+ ou similar
- Acesso root/sudo
- Conexão com internet
- Conta Oracle Cloud
- Conta Backblaze B2

## 🔧 Configuração

### VM Principal
```bash
# Configurar backup automático a cada 3h
echo "0 */3 * * * /opt/n8n-backup/backup.sh >> /opt/n8n-backup/logs/cron.log 2>&1" | sudo crontab -

# Verificar configuração
sudo crontab -l

# Backup manual (teste)
sudo ./backup.sh
```

### VM Standby
```bash
# Configuração inicial
sudo ./setup-standby.sh

# Configurar credenciais iguais à produção
# (Oracle, B2, senhas, etc.)
```

## 📞 Suporte

Para dúvidas ou problemas:
1. Verificar logs: `tail -f /opt/n8n-backup/logs/backup.log`
2. Health check: `/opt/n8n-backup/health-check.sh`
3. Documentação completa no README principal

---

**Esta arquitetura garante 99.9% de disponibilidade com custo mínimo.**
