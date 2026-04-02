#!/bin/bash
# DigitalTAK – Create Initial TAK Server User Groups
#
# Creates user groups via the TAK Server REST API using mutual TLS authentication
# with the admin client certificate.
#
# Groups specified in TAK_INIT_GROUPS (comma-separated) are created as SYSTEM
# groups that act as channels for organising users.
#
# Called by entrypoint.sh on first run only (after TAK Server is ready and the
# admin cert has been promoted).
#
# Required env vars:
#   TAK_INIT_GROUPS      Comma-separated group names (default: Alpha,Bravo)
#   TAK_CERT_PASS        Certificate keystore password (used to unlock admin.p12)
#   TAK_ADMIN_CERT_NAME  Admin cert basename (default: admin)

set -euo pipefail

CERTS_DIR="/opt/tak/certs/files"
TAK_API="https://localhost:8443"
ADMIN_CERT_NAME="${TAK_ADMIN_CERT_NAME:-admin}"
ADMIN_P12="${CERTS_DIR}/${ADMIN_CERT_NAME}.p12"
GROUPS="${TAK_INIT_GROUPS:-Alpha,Bravo}"

info() { echo "[GROUPS] $(date -u +%H:%M:%S) $*"; }
warn() { echo "[GROUPS WARN] $(date -u +%H:%M:%S) $*" >&2; }
die()  { echo "[GROUPS ERROR] $*" >&2; exit 1; }

[ -f "$ADMIN_P12" ] || die "Admin certificate not found at ${ADMIN_P12}"
[ -n "${TAK_CERT_PASS:-}" ] || die "TAK_CERT_PASS must be set"

# ── Create each group ─────────────────────────────────────────────────────────
IFS=',' read -ra group_list <<< "$GROUPS"
for group in "${group_list[@]}"; do
    # Trim whitespace
    group="$(echo "$group" | tr -d '[:space:]')"
    [ -n "$group" ] || continue

    info "Creating group: ${group}"

    http_code=$(curl -sk \
        --cert "${ADMIN_P12}:${TAK_CERT_PASS}" \
        --cert-type P12 \
        -o /tmp/group_response.json \
        -w "%{http_code}" \
        -X PUT \
        -H "Content-Type: application/json" \
        "${TAK_API}/Marti/api/groups/${group}?direction=BOTH&type=SYSTEM" \
        2>/dev/null)

    case "$http_code" in
        200|201)
            info "  Group '${group}' created successfully (HTTP ${http_code})."
            ;;
        409)
            info "  Group '${group}' already exists (HTTP 409). Skipping."
            ;;
        *)
            warn "  Unexpected HTTP ${http_code} creating group '${group}'."
            cat /tmp/group_response.json 2>/dev/null || true
            # Non-fatal: continue with remaining groups
            ;;
    esac
done

# ── Verify groups are visible ─────────────────────────────────────────────────
info "Verifying groups via GET /Marti/api/groups..."
groups_json=$(curl -sk \
    --cert "${ADMIN_P12}:${TAK_CERT_PASS}" \
    --cert-type P12 \
    "${TAK_API}/Marti/api/groups" 2>/dev/null)

for group in "${group_list[@]}"; do
    group="$(echo "$group" | tr -d '[:space:]')"
    [ -n "$group" ] || continue
    if echo "$groups_json" | grep -q "\"${group}\""; then
        info "  Verified: group '${group}' is present."
    else
        warn "  Warning: group '${group}' not found in group list after creation."
    fi
done

info "Group initialisation complete."
rm -f /tmp/group_response.json
