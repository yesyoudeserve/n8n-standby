# N8N Backup System v2.0 - Estrutura Simplificada

Sistema de backup automatizado para N8N com EasyPanel usando duas VMs: **Produção** e **Backup**.

## 🎯 Visão Geral

### Arquitetura

**VM de Produção:**
- EasyPanel já configurado e operacional
- Backup automático a cada 3 horas
- PostgreSQL + Redis completos
- Notificações Discord
- Limpeza automática (>7 dias)
- Upload para Oracle + B2

**VM de Backup:**
- EasyPanel pré-instalado e configurado
- Containers criados manualmente via schema
- Fica desligada (custo mínimo)
- Ativação sob demanda para DR
- Restaura último backup disponível

---

## 🚀 Quick Start

### VM de Produção

```bash
# 1. Download do projeto
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-standby/main/bootstrap.sh | bash
cd /opt/n8n-backup

# 2. Executar setup
sudo ./setup-prod.sh

# 3. Configurar credenciais
./lib/setup.sh interactive

# 4. Primeiro backup de teste
sudo ./backup-prod.sh
```

**Pronto!** Backups automáticos a cada 3 horas.

### VM de Backup

```bash
# 1. Download do projeto
curl -sSL https://raw.githubusercontent.com/yesyoudeserve/n8n-standby/main/bootstrap.sh | bash
cd /opt/n8n-backup

# 2. Executar setup (instala EasyPanel)
sudo ./setup-backup.sh

# 3. Configurar EasyPanel
# Acesse: https://SEU_IP:3000
# Crie usuário e senha

# 4. Importar schema dos containers (MANUAL)
# No EasyPanel, importe o schema salvo

# 5. Configurar credenciais
./lib/setup.sh interactive

# 6. Testar restauração
sudo ./restore-backup.sh
```

---

## 📋 Comandos Principais

### VM de Produção

```bash
# Backup manual
sudo ./backup-prod.sh

# Ver logs em tempo real
tail -f /opt/n8n-backup/logs/backup.log

# Ver logs do cron
tail -f /opt/n8n-backup/logs/cron.log

# Editar configurações
./lib/setup.sh edit
```

### VM de Backup

```bash
# Restaurar último backup
sudo ./restore-backup.sh

# Listar backups disponíveis
rclone lsl oracle:n8n-backups/
rclone lsl b2:n8n-backups-offsite/
```

---

## 🔧 Configuração

### Arquivo config.env

```bash
# === N8N ===
N8N_POSTGRES_PASSWORD="sua-senha"
N8N_ENCRYPTION_KEY="sua-chave"

# === ORACLE ===
ORACLE_ENABLED=true
ORACLE_NAMESPACE="seu-namespace"
ORACLE_REGION="eu-madrid-1"
ORACLE_ACCESS_KEY="sua-access-key"
ORACLE_SECRET_KEY="sua-secret-key"
ORACLE_BUCKET="n8n-backups"

# === B2 ===
B2_ENABLED=true
B2_ACCOUNT_ID="seu-account-id"
B2_APPLICATION_KEY="sua-app-key"
B2_BUCKET="n8n-backups-offsite"

# === RETENÇÃO ===
LOCAL_RETENTION_DAYS=2
REMOTE_RETENTION_DAILY=7

# === MONITORAMENTO ===
NOTIFY_WEBHOOK="https://discord.com/api/webhooks/..."
```

### Setup Interativo

```bash
./lib/setup.sh interactive
```

O sistema detecta automaticamente:
- Senha do PostgreSQL
- N8N Encryption Key
- Carrega credenciais do Supabase

---

## 📦 O que é Feito Backup

### PostgreSQL
- ✅ Todos os bancos de dados
- ✅ Dump completo com `pg_dumpall`
- ✅ Compactado com gzip

### Redis
- ✅ Arquivo dump.rdb completo
- ✅ Estado atual da memória

### Resultado
- Arquivo `.tar.gz` compactado
- Upload para Oracle + B2 (redundância)
- Hash SHA256 para verificação

---

## ⏰ Agendamento

### VM de Produção

Backup automático configurado via cron:

```bash
# A cada 3 horas
0 */3 * * * /opt/n8n-backup/backup-prod.sh >> /opt/n8n-backup/logs/cron.log 2>&1
```

**Horários de execução:**
- 00:00 (meia-noite)
- 03:00
- 06:00
- 09:00
- 12:00
- 15:00
- 18:00
- 21:00

### Verificar cron

```bash
crontab -l
```

---

## 🔔 Notificações Discord

Configure o webhook do Discord no `config.env`:

```bash
NOTIFY_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK"
```

### Eventos notificados:

- 🚀 Backup iniciado
- ✅ Backup concluído (com tamanho)
- ❌ Falha no backup
- 📤 Upload para Oracle/B2
- 🧹 Limpeza de backups antigos

---

## 🧹 Limpeza Automática

### Local (VM)
- Mantém últimos **2 dias**
- Limpa automaticamente após cada backup

### Remoto (Oracle + B2)
- Mantém últimos **7 dias**
- Limpa automaticamente após cada backup

---

## 🆘 Disaster Recovery

### Cenário: VM de Produção falhou

```bash
# 1. Ligar VM de Backup
# (na Oracle Cloud Console)

# 2. Restaurar último backup
sudo ./restore-backup.sh

# 3. Escolher storage (Oracle ou B2)

# 4. Confirmar restauração
# Digite: RESTAURAR

# 5. Aguardar conclusão
# PostgreSQL + Redis restaurados

# 6. Verificar containers
docker ps

# 7. Acessar N8N
# http://SEU_IP:5678
```

**Tempo estimado:** 5-15 minutos (dependendo do tamanho do backup)

---

## 📊 Estrutura de Arquivos

```
/opt/n8n-backup/
├── backup-prod.sh          # Script de backup (VM Produção)
├── restore-backup.sh       # Script de restauração (VM Backup)
├── setup-prod.sh           # Setup VM Produção
├── setup-backup.sh         # Setup VM Backup
├── config.env              # Configurações
│
├── lib/
│   ├── setup.sh            # Setup interativo
│   ├── logger.sh           # Funções de log
│   └── generate-rclone.sh  # Gerador rclone.conf
│
├── backups/
│   └── local/              # Backups locais temporários
│
├── schemas/                # Schemas do EasyPanel
│   └── easypanel-schema.json
│
└── logs/
    ├── backup.log          # Log principal
    └── cron.log            # Log do cron
```

---

## 🔐 Segurança

### Credenciais Armazenadas

- **Supabase:** Metadados criptografados com senha mestra
- **Oracle/B2:** Arquivos de configuração criptografados
- **Local:** config.env com permissões restritas

### Boas Práticas

1. ✅ Use senha mestra forte
2. ✅ Mantenha backup das credenciais offline
3. ✅ Configure webhooks Discord privados
4. ✅ Use chaves de API com permissões mínimas
5. ✅ Monitore logs regularmente

---

## 🐛 Troubleshooting

### Backup não está rodando

```bash
# Verificar cron
crontab -l

# Ver logs
tail -f /opt/n8n-backup/logs/cron.log
tail -f /opt/n8n-backup/logs/backup.log

# Testar backup manual
sudo ./backup-prod.sh
```

### Falha no upload

```bash
# Testar rclone
rclone lsd oracle:
rclone lsd b2:

# Verificar credenciais
cat /opt/n8n-backup/config.env
```

### Restauração falhou

```bash
# Verificar containers
docker ps -a

# Ver logs do PostgreSQL
docker logs n8n_postgres

# Reiniciar containers
docker restart n8n_postgres n8n_redis
```

---

## 📝 Changelog

### v2.0 - Nova Estrutura
- ✅ Separação clara: VM Produção vs VM Backup
- ✅ Backup PostgreSQL completo (todos os bancos)
- ✅ Backup Redis completo
- ✅ Backup a cada 3 horas
- ✅ Notificações Discord aprimoradas
- ✅ Script de restauração simplificado
- ✅ Remoção de complexidade do EasyPanel backup

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verifique os logs
2. Consulte a documentação
3. Abra uma issue no GitHub

---

## 📄 Licença

MIT License

---

**Desenvolvido com ❤️ para facilitar backups do N8N + EasyPanel**