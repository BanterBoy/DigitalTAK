#!/bin/bash
# DigitalTAK – TAK Server Docker Entrypoint
#
# Orchestrates first-run initialisation and subsequent container startups:
#   1. Validate required environment variables
#   2. Wait for PostgreSQL to be ready
#   3. Patch CoreConfig.xml for external database (idempotent)
#   4. Generate CA chain + server/admin certs on first run (idempotent)
#   5. Promote admin certificate in TAK Server database
#   6. Start TAK Server
#   7. Create initial user groups via REST API (first run only)
#   8. Monitor process health and forward SIGTERM for clean shutdown

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INIT_SENTINEL="/opt/tak/.docker_initialized"
TAK_LOG="/opt/tak/logs/takserver.log"
TAKSERVER_STARTUP_TIMEOUT=300   # seconds to wait for HTTP 200 on 8443

# ── Colour helpers ────────────────────────────────────────────────────────────
info()    { echo "[INFO]  $(date -u +%H:%M:%S) $*"; }
warn()    { echo "[WARN]  $(date -u +%H:%M:%S) $*" >&2; }
error()   { echo "[ERROR] $(date -u +%H:%M:%S) $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Validate required env vars ────────────────────────────────────────────────
info "Validating environment variables..."
required_vars=(
    TAK_DB_HOST TAK_DB_PORT TAK_DB_NAME TAK_DB_USER TAK_DB_PASSWORD
    TAK_CERT_STATE TAK_CERT_CITY TAK_CERT_ORG TAK_CERT_OU TAK_CERT_PASS
)
for var in "${required_vars[@]}"; do
    [ -n "${!var:-}" ] || die "Required environment variable '$var' is not set."
done
info "All required environment variables are set."

# ── Wait for PostgreSQL ───────────────────────────────────────────────────────
info "Waiting for PostgreSQL at ${TAK_DB_HOST}:${TAK_DB_PORT}..."
max_pg_wait=120
elapsed=0
until pg_isready -h "$TAK_DB_HOST" -p "$TAK_DB_PORT" -U "$TAK_DB_USER" -d "$TAK_DB_NAME" -q; do
    [ "$elapsed" -ge "$max_pg_wait" ] && die "PostgreSQL did not become ready within ${max_pg_wait}s."
    sleep 3
    elapsed=$(( elapsed + 3 ))
    info "  ${elapsed}/${max_pg_wait}s — waiting for PostgreSQL..."
done
info "PostgreSQL is ready."

# ── Patch CoreConfig.xml for external database (idempotent) ──────────────────
info "Configuring database connection in CoreConfig.xml..."
"$SCRIPT_DIR/configure-db.sh"

# ── First-run: generate certificates ─────────────────────────────────────────
if [ ! -f "$INIT_SENTINEL" ]; then
    info "First-run detected — generating TAK Server certificate chain..."
    "$SCRIPT_DIR/cert-gen.sh"
else
    info "Certificates already generated (sentinel found). Skipping cert generation."
fi

# ── Start TAK Server ──────────────────────────────────────────────────────────
info "Starting TAK Server..."
mkdir -p /opt/tak/logs

# TAK Server uses a wrapper script to launch the messaging and API Java processes.
# We start it then monitor the PID files it creates.
/opt/tak/takserver.sh start || {
    # On first run the script may exit non-zero before PID files appear — not fatal.
    warn "takserver.sh returned non-zero; checking if processes started anyway..."
}

# ── Wait for TAK Server to be ready ──────────────────────────────────────────
info "Waiting for TAK Server HTTPS API on port 8443 (timeout ${TAKSERVER_STARTUP_TIMEOUT}s)..."
elapsed=0
ready=false
while [ "$elapsed" -lt "$TAKSERVER_STARTUP_TIMEOUT" ]; do
    if curl -sk --max-time 5 "https://localhost:8443/Marti/api/version" | grep -q '"version"' 2>/dev/null; then
        ready=true
        break
    fi
    sleep 10
    elapsed=$(( elapsed + 10 ))
    info "  ${elapsed}/${TAKSERVER_STARTUP_TIMEOUT}s — waiting for TAK Server..."
done

if ! $ready; then
    error "TAK Server did not start within ${TAKSERVER_STARTUP_TIMEOUT}s."
    # Print recent logs to help diagnose the failure
    tail -n 50 "$TAK_LOG" 2>/dev/null || true
    die "Aborting."
fi
info "TAK Server is ready."

# ── First-run: promote admin certificate ──────────────────────────────────────
if [ ! -f "$INIT_SENTINEL" ]; then
    info "Promoting admin certificate..."
    java -jar /opt/tak/utils/UserManager.jar certmod \
        -A /opt/tak/certs/files/"${TAK_ADMIN_CERT_NAME:-admin}".pem \
        || die "Admin promotion failed. Check /opt/tak/logs for details."
    info "Admin certificate promoted successfully."

    # ── First-run: create initial user groups ────────────────────────────────
    info "Creating initial user groups: ${TAK_INIT_GROUPS:-Alpha,Bravo}"
    "$SCRIPT_DIR/init-groups.sh"

    # ── Mark initialisation complete ─────────────────────────────────────────
    touch "$INIT_SENTINEL"
    info "First-run initialisation complete. Sentinel written to ${INIT_SENTINEL}."
fi

info "======================================================================"
info " TAK Server 5.7 is running."
info ""
info "  WebTAK / Admin:        https://<host>:${TAK_PORT_WEB:-8443}"
info "  CoT clients (TLS):     <host>:${TAK_PORT_COT:-8089}"
info "  Cert enrollment:       https://<host>:${TAK_PORT_ENROLL:-8446}"
info ""
info "  Admin cert (copy to host for browser import):"
info "    docker cp \$(docker compose ps -q takserver):/opt/tak/certs/files/admin.p12 ."
info "======================================================================"

# ── Signal handling for clean shutdown ───────────────────────────────────────
shutdown() {
    info "Received shutdown signal — stopping TAK Server..."
    /opt/tak/takserver.sh stop 2>/dev/null || true
    info "TAK Server stopped."
    exit 0
}
trap shutdown SIGTERM SIGINT

# ── Health monitor: exit if TAK Server processes die ─────────────────────────
# This lets Docker restart the container automatically.
while true; do
    if ! pgrep -f "takserver" > /dev/null 2>&1; then
        error "TAK Server processes not detected. Container will exit to trigger restart."
        exit 1
    fi
    sleep 30
done
