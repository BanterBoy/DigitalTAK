---
layout: page
title: Database Backup & Recovery
nav_title: Database Backup
---

# TAK Server Database Backup & Recovery

TAK Server stores all application state — users, missions, certificates, groups, CoT history, and server configuration — in a PostgreSQL 16 database named `cot_router`. Certificates and `.p12` files are **not** in the database; they live in `/opt/tak/certs/files/` on the server filesystem.

---

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## 1. What Is and Isn't in the Database

| Data | Location | In backup? |
|------|----------|-----------|
| Users, passwords, groups | PostgreSQL `cot_router` | Yes |
| Missions and mission content | PostgreSQL `cot_router` | Yes |
| CoT event history | PostgreSQL `cot_router` | Yes |
| Server configuration | PostgreSQL `cot_router` | Yes |
| CA, server, and admin certificates | `/opt/tak/certs/files/*.pem/.jks/.p12` | No — back up separately |
| Let's Encrypt certificates | `/etc/letsencrypt/` | No — back up separately |
| `CoreConfig.xml` | `/opt/tak/CoreConfig.xml` | No — back up separately |

A complete recovery requires restoring both the PostgreSQL dump **and** the certificate files.

---

## 2. Manual Backup (pg_dump)

Run as the `tak` system user (which owns the PostgreSQL role):

```bash
# Connect to the TAK Server over SSH
ssh atak@<server-ip>

# Create a timestamped backup
sudo -u tak pg_dump -U tak cot_router > /tmp/tak-backup-$(date +%Y%m%d-%H%M).sql

# Verify the file is non-zero
ls -lh /tmp/tak-backup-*.sql
```

To include all databases and global roles (recommended for full-server recovery):

```bash
sudo -u postgres pg_dumpall > /tmp/tak-dumpall-$(date +%Y%m%d-%H%M).sql
```

### Copy the backup to your Windows workstation

```powershell
$sftp = New-SFTPSession -ComputerName <server-ip> -Credential $cred -AcceptKey
Get-SFTPItem -SessionId $sftp.SessionId `
    -Path '/tmp/tak-backup-20260424-1200.sql' `
    -Destination '.\backups\'
Remove-SFTPSession -SessionId $sftp.SessionId
```

---

## 3. Automated Daily Backups (Cron)

Add a daily cron job on the TAK Server that backs up to a local directory, retaining the last 7 days:

```bash
sudo tee /etc/cron.daily/tak-db-backup > /dev/null << 'EOF'
#!/bin/bash
BACKUP_DIR=/opt/tak/backups
mkdir -p "$BACKUP_DIR"
FILENAME="$BACKUP_DIR/tak-cot_router-$(date +%Y%m%d).sql"
sudo -u tak pg_dump -U tak cot_router > "$FILENAME"
# Retain last 7 daily backups
find "$BACKUP_DIR" -name 'tak-cot_router-*.sql' -mtime +7 -delete
EOF

sudo chmod +x /etc/cron.daily/tak-db-backup
```

Verify the script runs cleanly:

```bash
sudo /etc/cron.daily/tak-db-backup
ls -lh /opt/tak/backups/
```

> **Offsite copies:** Copy backups to your Windows workstation or cloud storage periodically. The TAK Server VM itself is a single point of failure — local-only backups provide no protection against disk corruption or VM deletion.

---

## 4. Backup Certificate Files

Back up the cert directory alongside the database dump:

```bash
sudo tar czf /tmp/tak-certs-$(date +%Y%m%d).tar.gz /opt/tak/certs/files/
```

Copy to Windows:

```powershell
Get-SFTPItem -SessionId $sftp.SessionId `
    -Path '/tmp/tak-certs-20260424.tar.gz' `
    -Destination '.\backups\'
```

---

## 5. Restore Procedure

### 5.1 Stop TAK Server

```bash
sudo systemctl stop takserver
```

### 5.2 Drop and Recreate the Database

```bash
sudo -u postgres psql -c "DROP DATABASE IF EXISTS cot_router;"
sudo -u postgres psql -c "CREATE DATABASE cot_router OWNER tak;"
```

### 5.3 Restore from Dump

```bash
sudo -u tak psql -U tak cot_router < /tmp/tak-backup-20260424-1200.sql
```

### 5.4 Restore Certificate Files (if needed)

```bash
sudo tar xzf /tmp/tak-certs-20260424.tar.gz -C /
sudo chown -R tak:tak /opt/tak/certs/files/
sudo chmod 750 /opt/tak/certs/files/
```

### 5.5 Restart TAK Server

```bash
sudo systemctl start takserver

# Watch for "Server is running and ready to serve"
sudo journalctl -u takserver -f
```

### 5.6 Validate

After restart, connect with TAKServerPS and confirm data:

```powershell
Connect-TAKServer -HostName <server-ip> -PfxPath .\admin.p12 -PfxPassword $pass -SkipCertificateCheck $true
Get-TAKUser
Get-TAKMission
Get-TAKVersion
```

---

## 6. Disaster Recovery Checklist

| Step | Command / Action |
|------|-----------------|
| 1. Stop TAK Server | `systemctl stop takserver` |
| 2. Drop database | `psql -c "DROP DATABASE cot_router;"` |
| 3. Recreate database | `psql -c "CREATE DATABASE cot_router OWNER tak;"` |
| 4. Restore SQL dump | `psql -U tak cot_router < backup.sql` |
| 5. Restore cert files | `tar xzf tak-certs.tar.gz -C /` |
| 6. Fix permissions | `chown -R tak:tak /opt/tak/certs/files/` |
| 7. Start TAK Server | `systemctl start takserver` |
| 8. Validate | `Get-TAKUser`, `Get-TAKMission`, `Get-TAKVersion` |

---

## References

- [TAK Server 5.7 Configuration Guide](../TAK_Server_Configuration_Guide_5.7.pdf) — PostgreSQL configuration in Appendix D
- [Troubleshooting](../../troubleshooting/) — TAK Server service failures and diagnostics
- [Baseline Configuration](./baseline.md) — full inventory of files managed outside the database
