#!/bin/bash
# DigitalTAK – Configure CoreConfig.xml for External PostgreSQL
#
# Patches the JDBC connection URL, username, and password in CoreConfig.xml
# to point at the Docker Compose 'db' container instead of localhost.
#
# Idempotent: checks whether the connection URL already contains $TAK_DB_HOST
# before making any changes.
#
# Required env vars:
#   TAK_DB_HOST      PostgreSQL hostname (docker service name, e.g. "db")
#   TAK_DB_PORT      PostgreSQL port (default: 5432)
#   TAK_DB_NAME      Database name (default: cot)
#   TAK_DB_USER      Database username (default: martiuser)
#   TAK_DB_PASSWORD  Database password

set -euo pipefail

CORE_CONFIG="/opt/tak/CoreConfig.xml"

info() { echo "[DB-CFG] $(date -u +%H:%M:%S) $*"; }
die()  { echo "[DB-CFG ERROR] $*" >&2; exit 1; }

[ -f "$CORE_CONFIG" ] || die "CoreConfig.xml not found at $CORE_CONFIG"

TAK_DB_HOST="${TAK_DB_HOST:-db}"
TAK_DB_PORT="${TAK_DB_PORT:-5432}"
TAK_DB_NAME="${TAK_DB_NAME:-cot}"
TAK_DB_USER="${TAK_DB_USER:-martiuser}"

[ -n "${TAK_DB_PASSWORD:-}" ] || die "TAK_DB_PASSWORD must be set."

# ── Idempotency check ─────────────────────────────────────────────────────────
target_url="jdbc:postgresql://${TAK_DB_HOST}:${TAK_DB_PORT}/${TAK_DB_NAME}"
if grep -qF "$target_url" "$CORE_CONFIG"; then
    info "CoreConfig.xml already configured for ${target_url}. No changes needed."
    exit 0
fi

info "Patching CoreConfig.xml database connection..."
info "  Target: ${target_url}"
info "  User:   ${TAK_DB_USER}"

# Helper: escape a value for use in a sed replacement string (| delimiter)
sed_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\&/g'; }

escaped_pass="$(sed_escape "$TAK_DB_PASSWORD")"
escaped_user="$(sed_escape "$TAK_DB_USER")"
escaped_url="$(sed_escape "$target_url")"

# TAK Server 5.7 CoreConfig.xml connection element format:
#   <connection url="jdbc:postgresql://127.0.0.1:5432/cot"
#               username="martiuser" password="..." sslEnabled="false"/>
#
# We use xmlstarlet for reliable XML editing. Falls back to sed if not available.

if command -v xmlstarlet &>/dev/null; then
    info "Using xmlstarlet to patch CoreConfig.xml..."
    xmlstarlet ed --inplace \
        -u "//repository/connection/@url"      -v "$target_url" \
        -u "//repository/connection/@username" -v "$TAK_DB_USER" \
        -u "//repository/connection/@password" -v "$TAK_DB_PASSWORD" \
        "$CORE_CONFIG"
else
    info "xmlstarlet not found — falling back to sed patch..."
    # Replace the connection url attribute (handles 127.0.0.1 or localhost)
    sed -i -E \
        "s|url=\"jdbc:postgresql://[^\"]+\"|url=\"${escaped_url}\"|g" \
        "$CORE_CONFIG"
    sed -i -E \
        "s|username=\"[^\"]+\"|username=\"${escaped_user}\"|g" \
        "$CORE_CONFIG"
    # Password replacement — only within the connection element line
    sed -i -E \
        "s|(.*connection.*url=.*username=.*)password=\"[^\"]*\"|\1password=\"${escaped_pass}\"|g" \
        "$CORE_CONFIG"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
if grep -qF "$target_url" "$CORE_CONFIG"; then
    info "CoreConfig.xml database connection patched successfully."
else
    die "Patch verification failed — expected URL '${target_url}' not found in CoreConfig.xml."
fi
