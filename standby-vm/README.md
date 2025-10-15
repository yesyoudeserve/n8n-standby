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

## 🚀 Como Usar

### 1. Configurar VM Standby (Uma Vez)

```bash
# Opção 1: Bootstrap automático (recomendado)
curl -fsSL https://raw.githubusercontent.com/yesyoudeserve/n8n-backup/main/standby-vm/bootstrap-standby.sh | bash
cd /opt/n8n-standby
sudo ./setup-standby.sh

# Opção 2: Manual
git clone https://github.com/yesyoudeserve/n8n-backup.git
cd n8n-backup/standby-vm
sudo ./setup-standby.sh
```

### 2. Backup Automático na VM Principal

```bash
# Na VM Principal (já configurada)
# Backup automático roda a cada 3h via cron
# Ou manual:
sudo ./backup.sh
```

### 3. Sincronização da VM Standby

```bash
# Quando precisar ativar a VM Standby:
cd /opt/n8n-standby  # ou o diretório onde estão os arquivos
sudo ./sync-standby.sh
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
