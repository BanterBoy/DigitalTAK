#!/bin/bash
# tak-team-certs.sh
#
# Generates per-user client certificates for a TAK Server team.
# Must run as the 'tak' user (or via sudo -u tak) from /opt/tak/certs/.
#
# Usage:
#   TEAM_NAME=alpha TEAM_SIZE=10 TAK_CERT_PASS=<pass> bash tak-team-certs.sh
#   bash tak-team-certs.sh --team alpha --size 10
#
# Outputs per-user .p12 files and a manifest JSON in:
#   /opt/tak/certs/files/teams/<TEAM_NAME>/
#
# SECURITY: Private keys are never printed to stdout.  Pass the keystore
# passphrase via TAK_CERT_PASS env var or the script will prompt securely.

set -euo pipefail

# ── Parse arguments ────────────────────────────────────────────────────────────
TEAM_NAME="${TEAM_NAME:-}"
TEAM_SIZE="${TEAM_SIZE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --team)  TEAM_NAME="$2"; shift 2 ;;
        --size)  TEAM_SIZE="$2"; shift 2 ;;
        *)       echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [[ -z "$TEAM_NAME" ]]; then
    read -r -p "Team name (e.g. alpha): " TEAM_NAME
fi
if [[ -z "$TEAM_SIZE" ]]; then
    read -r -p "Team size (10 or 20): " TEAM_SIZE
fi

# Normalise and validate
TEAM_NAME_LOWER="${TEAM_NAME,,}"
if [[ ! "$TEAM_NAME_LOWER" =~ ^[a-z0-9-]+$ ]]; then
    echo "ERROR: Team name must be lowercase letters, digits, and hyphens only."
    exit 1
fi
if [[ "$TEAM_SIZE" != "10" && "$TEAM_SIZE" != "20" ]]; then
    echo "ERROR: Team size must be 10 or 20."
    exit 1
fi

# ── Passphrase ─────────────────────────────────────────────────────────────────
# Read from env var; if absent, prompt securely (never echoed).
if [[ -z "${TAK_CERT_PASS:-}" ]]; then
    read -r -s -p "TAK certificate keystore passphrase: " TAK_CERT_PASS
    echo ""
    read -r -s -p "Confirm passphrase: " TAK_CERT_PASS_CONFIRM
    echo ""
    if [[ "$TAK_CERT_PASS" != "$TAK_CERT_PASS_CONFIRM" ]]; then
        echo "ERROR: Passphrases do not match."
        exit 1
    fi
fi

if [[ -z "$TAK_CERT_PASS" ]]; then
    echo "ERROR: Passphrase cannot be empty."
    exit 1
fi

# ── Build user list ────────────────────────────────────────────────────────────
# Team composition:
#   1  Team Lead      →  <team>-lead
#   1  Assistant Lead →  <team>-asst-lead
#   N  Operators      →  <team>-op-01 … <team>-op-NN  (N = size - 2)
declare -a USERNAMES
declare -a ROLES

USERNAMES+=( "${TEAM_NAME_LOWER}-lead" )
ROLES+=( "Team Lead" )

USERNAMES+=( "${TEAM_NAME_LOWER}-asst-lead" )
ROLES+=( "Assistant Lead" )

OPERATOR_COUNT=$(( TEAM_SIZE - 2 ))
for i in $(seq -w 1 "$OPERATOR_COUNT"); do
    USERNAMES+=( "${TEAM_NAME_LOWER}-op-${i}" )
    ROLES+=( "Operator" )
done

# ── Verify working directory ───────────────────────────────────────────────────
if [[ ! -f "makeCert.sh" ]]; then
    echo "ERROR: makeCert.sh not found. Run this script from /opt/tak/certs/."
    exit 1
fi

TEAM_OUT_DIR="files/teams/${TEAM_NAME_LOWER}"
mkdir -p "$TEAM_OUT_DIR"

echo ""
echo "Generating ${TEAM_SIZE}-person team: ${TEAM_NAME_LOWER}"
echo "Output → $(pwd)/${TEAM_OUT_DIR}"
echo ""

# ── Generate certificates ──────────────────────────────────────────────────────
# makeCert.sh client <name> creates:
#   files/<name>.p12  (PKCS12, passphrase = contents of cert-metadata.sh CAPASS)
# We then copy to the team output directory.
#
# makeCert.sh reads the passphrase from cert-metadata.sh CAPASS field.
# The operator must ensure cert-metadata.sh CAPASS matches TAK_CERT_PASS
# (createTakCerts.sh sets this during initial CA creation).

for i in "${!USERNAMES[@]}"; do
    USERNAME="${USERNAMES[$i]}"
    ROLE="${ROLES[$i]}"
    P12_SRC="files/${USERNAME}.p12"
    P12_DST="${TEAM_OUT_DIR}/${USERNAME}.p12"

    if [[ -f "$P12_DST" ]]; then
        echo "  [SKIP] ${USERNAME} (.p12 already exists)"
        continue
    fi

    echo "  [CERT] ${USERNAME} (${ROLE})"
    # Suppress stdout from makeCert.sh to avoid leaking key material in CI logs;
    # stderr is preserved for error surfacing.
    ./makeCert.sh client "$USERNAME" > /dev/null

    if [[ ! -f "$P12_SRC" ]]; then
        echo "ERROR: Expected $P12_SRC not found after makeCert.sh."
        exit 1
    fi

    cp "$P12_SRC" "$P12_DST"
done

# ── Copy CA truststore ────────────────────────────────────────────────────────
# Clients need the intermediate CA truststore to verify the server cert.
TRUSTSTORE_SRC="files/truststore-intermediate-ca.jks"
if [[ -f "$TRUSTSTORE_SRC" ]]; then
    cp "$TRUSTSTORE_SRC" "${TEAM_OUT_DIR}/truststore-intermediate-ca.jks"
fi

# ── Write manifest JSON ────────────────────────────────────────────────────────
MANIFEST_FILE="${TEAM_OUT_DIR}/manifest.json"

{
    echo "{"
    echo "  \"team\": \"${TEAM_NAME_LOWER}\","
    echo "  \"size\": ${TEAM_SIZE},"
    echo "  \"generated\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"users\": ["
    for i in "${!USERNAMES[@]}"; do
        USERNAME="${USERNAMES[$i]}"
        ROLE="${ROLES[$i]}"
        COMMA=","
        [[ $i -eq $(( ${#USERNAMES[@]} - 1 )) ]] && COMMA=""
        echo "    {\"username\": \"${USERNAME}\", \"role\": \"${ROLE}\", \"cert\": \"${USERNAME}.p12\"}${COMMA}"
    done
    echo "  ]"
    echo "}"
} > "$MANIFEST_FILE"

echo ""
echo "── Certificate generation complete ──────────────────────────────────────"
echo "  Team    : ${TEAM_NAME_LOWER}"
echo "  Users   : ${TEAM_SIZE}"
echo "  Output  : $(pwd)/${TEAM_OUT_DIR}"
echo "  Manifest: ${MANIFEST_FILE}"
echo ""
echo "Next step: run New-TAKDataPackage.ps1 on the Windows host to bundle"
echo "           each user's .p12 into an ATAK-compatible data package."
echo ""
echo "IMPORTANT: ${TEAM_OUT_DIR}/*.p12 files contain private keys."
echo "           Transfer securely (SCP/SFTP) and delete from server after distribution."
