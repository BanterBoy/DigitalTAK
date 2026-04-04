# TAK Server 5.7 – Docker Compose Deployment Runbook

Deploy a fully operational TAK Server instance on a Rocky Linux 9 Hyper-V guest using Docker Compose. All configuration lives in version-controlled files; the only manual step is providing the TAK Server RPM.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Rocky Linux 9 Hyper-V guest | 9.5+ | Provisioned by `Deploy-TAKServer.ps1` or manually |
| Docker Engine | 24+ | Install via steps below |
| Docker Compose | v2 (plugin) | Bundled with Docker Engine 24+ |
| TAK Server RPM | 5.7-RELEASE8 | Free download from [tak.gov](https://tak.gov) |
| Internet access (build time only) | — | To pull Rocky Linux and PostgreSQL base images |

---

## 1 — Install Docker on Rocky Linux 9

Run once on the host after the VM is provisioned:

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
# Allow the current user to run docker without sudo
sudo usermod -aG docker "$USER"
newgrp docker
```

Verify:

```bash
docker version
docker compose version
```

---

## 2 — Obtain the TAK Server RPM

1. Create a free account at [tak.gov](https://tak.gov).
2. Download `takserver-5.7-RELEASE8.noarch.rpm`.
3. Optionally download `takserver-public-gpg.key` for RPM signature verification (recommended).
4. Copy both files into the `docker/` directory of this repository:

```bash
cp ~/Downloads/takserver-5.7-RELEASE8.noarch.rpm /path/to/DigitalTAK/docker/
cp ~/Downloads/takserver-public-gpg.key           /path/to/DigitalTAK/docker/
```

---

## 3 — Configure the Environment

```bash
cd docker/
cp .env.example .env
nano .env   # or vi, code, etc.
```

### Required values to change

| Variable | Description | Example |
|---|---|---|
| `TAK_DB_PASSWORD` | PostgreSQL password for the TAK database user | `<your-db-password>` |
| `TAK_CERT_STATE` | State code — UPPERCASE, no spaces | `VA` |
| `TAK_CERT_CITY` | City code — UPPERCASE, no spaces | `ARLINGTON` |
| `TAK_CERT_ORG` | Organisation — UPPERCASE, no spaces | `MYORG` |
| `TAK_CERT_OU` | Org unit — UPPERCASE, no spaces | `MYUNIT` |
| `TAK_CERT_PASS` | Certificate keystore password | `<your-cert-password>` |

All other variables have sensible defaults and can be left unchanged for a baseline deployment.

> **Security**: `.env` is excluded by `.gitignore`. Never commit it to version control.

---

## 4 — Build the TAK Server Image

This step installs the RPM into a Rocky Linux 9 container image. It requires internet access to pull the base image and install dependencies.

```bash
cd docker/
docker compose build
```

Expected build time: 5–15 minutes depending on download speed.

---

## 5 — Start the Stack

```bash
docker compose up -d
```

What happens on first start:

1. PostgreSQL starts and creates the `cot` database.
2. TAK Server container starts and waits for PostgreSQL to be ready.
3. `CoreConfig.xml` is patched to use the Docker Compose database service.
4. A Root CA → Intermediate CA → server cert → admin cert chain is generated.
5. TAK Server starts and runs Flyway database migrations.
6. The admin certificate is promoted to TAK Server administrator.
7. Alpha and Bravo user groups are created via the REST API.
8. A sentinel file (`/opt/tak/.docker_initialized`) is written so steps 4–7 are skipped on subsequent restarts.

### Monitor startup

```bash
docker compose logs -f takserver
```

TAK Server is ready when you see:

```
[INFO] TAK Server is ready.
```

Typical startup time: 2–4 minutes.

---

## 6 — Verify the Deployment

### Health check

```bash
docker compose ps
```

Both `db` and `takserver` should show `healthy`.

### API version check

```bash
curl -sk https://localhost:8443/Marti/api/version
# Expected: {"version": "5.7-RELEASE8", ...}
```

### WebTAK admin console

1. Copy the admin certificate from the container to your local machine:

```bash
docker compose cp takserver:/opt/tak/certs/files/admin.p12 ~/admin.p12
```

2. Import `admin.p12` into Firefox or Chrome (Settings → Certificates → Import).
   Password: the value you set for `TAK_CERT_PASS` in `.env`.

3. Navigate to `https://<vm-ip>:8443` in your browser.

### Verify Alpha and Bravo groups

```bash
curl -sk --cert ~/admin.p12 --cert-type P12 --pass "$TAK_CERT_PASS" \
  https://localhost:8443/Marti/api/groups | python3 -m json.tool
```

Both `Alpha` and `Bravo` should appear in the response.

---

## 7 — Connect a TAK Client (ATAK / WinTAK)

1. Generate a client certificate using the PowerShell `TAKServerPS` module, or use the certificate enrollment endpoint at `https://<vm-ip>:8446`.
2. Configure the TAK client:
   - **Server**: `<vm-ip>`
   - **Port**: `8089`
   - **Protocol**: TLS
   - **Trust store**: install the CA chain or use the enrollment flow.

---

## Day-2 Operations

### Restart

```bash
docker compose restart takserver
```

### Stop / Start

```bash
docker compose stop
docker compose start
```

### View logs

```bash
docker compose logs --tail=100 -f takserver
docker compose logs --tail=100 -f db
```

Logs are also persisted in the `tak_logs` Docker volume.

### Upgrade TAK Server

1. Place the new RPM in `docker/`.
2. Update `TAK_RPM_FILENAME` in `.env`.
3. Rebuild the image:

```bash
docker compose build --no-cache takserver
```

4. Restart the stack:

```bash
docker compose up -d
```

The database volumes are preserved; TAK Server will run Flyway migrations on startup.

### Backup

Back up the named volumes before any upgrade or maintenance window:

```bash
# PostgreSQL data
docker run --rm -v digitaktak_postgres_data:/data \
  -v "$(pwd)":/backup alpine \
  tar czf /backup/postgres_data_$(date +%Y%m%d).tar.gz -C /data .

# Certificate files
docker run --rm -v digitaktak_tak_certs:/data \
  -v "$(pwd)":/backup alpine \
  tar czf /backup/tak_certs_$(date +%Y%m%d).tar.gz -C /data .
```

### Regenerate certificates

Delete the sentinel and the cert volume, then restart:

```bash
docker compose stop takserver
docker volume rm digitaktak_tak_certs
docker compose up -d
```

> **Warning**: Regenerating certs invalidates all existing client `.p12` files. Redistribute new client certificates to all TAK clients.

---

## Firewall Rules

The following ports must be open on the Rocky Linux host firewall:

```bash
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp   # CoT clients
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp   # WebTAK / API
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp   # Cert enrollment
sudo firewall-cmd --reload
```

---

## Troubleshooting

### TAK Server fails to start — database connection refused

Check that PostgreSQL is healthy and the env vars match:

```bash
docker compose ps db
docker compose logs db
```

Verify `TAK_DB_HOST`, `TAK_DB_NAME`, `TAK_DB_USER`, and `TAK_DB_PASSWORD` in `.env` are consistent.

### Certificate generation fails

Check the cert-gen logs:

```bash
docker compose logs takserver | grep -A5 '\[CERTS'
```

Common cause: `TAK_CERT_STATE/CITY/ORG/OU` contain lowercase letters or spaces. All values must be UPPERCASE with only letters, digits, and hyphens.

### CoreConfig.xml not patched

If TAK Server tries to connect to `127.0.0.1`, the DB patch did not apply:

```bash
docker compose exec takserver grep "connection url" /opt/tak/CoreConfig.xml
```

Should show `jdbc:postgresql://db:5432/cot`. If not, delete the sentinel and restart:

```bash
docker compose exec takserver rm /opt/tak/.docker_initialized
docker compose restart takserver
```

### Image build fails — RPM not found

Ensure the RPM filename in `docker/` matches `TAK_RPM_FILENAME` in `.env` (default: `takserver-5.7-RELEASE8.noarch.rpm`).

---

## File Reference

| File | Purpose |
|---|---|
| `docker/Dockerfile` | Builds the TAK Server container image from Rocky Linux 9 |
| `docker/docker-compose.yml` | Orchestrates TAK Server + PostgreSQL services |
| `docker/.env.example` | Template for all configurable variables |
| `docker/.env` | Your local secrets (excluded from git) |
| `docker/scripts/entrypoint.sh` | Container init orchestrator |
| `docker/scripts/cert-gen.sh` | Non-interactive certificate generation |
| `docker/scripts/configure-db.sh` | Patches CoreConfig.xml for external DB |
| `docker/scripts/init-groups.sh` | Creates Alpha/Bravo groups via REST API |
| `docker/scripts/healthcheck.sh` | Docker health check probe |
