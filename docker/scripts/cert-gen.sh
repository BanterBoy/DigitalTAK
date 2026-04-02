#!/bin/bash
# DigitalTAK – Non-interactive TAK Server Certificate Generation
#
# Replicates what InstallShellScripts/createTakCerts.sh does interactively,
# reading all inputs from environment variables instead of stdin prompts.
#
# Required env vars (set via docker-compose.yml / .env):
#   TAK_CERT_STATE    State code      — UPPERCASE, no spaces (e.g. VA)
#   TAK_CERT_CITY     City code       — UPPERCASE, no spaces (e.g. ARLINGTON)
#   TAK_CERT_ORG      Organisation    — UPPERCASE, no spaces (e.g. MYORG)
#   TAK_CERT_OU       Org unit        — UPPERCASE, no spaces (e.g. MYUNIT)
#   TAK_CERT_CA_NAME  Root CA name    — default: TAK-CA
#   TAK_CERT_PASS     Keystore password
#
# Idempotency: this script is only called by entrypoint.sh when the first-run
# sentinel does NOT exist, so it only runs once per volume lifecycle.

set -euo pipefail

CERTS_DIR="/opt/tak/certs"

info()  { echo "[CERTS] $(date -u +%H:%M:%S) $*"; }
die()   { echo "[CERTS ERROR] $*" >&2; exit 1; }

# ── Validate inputs ───────────────────────────────────────────────────────────
for var in TAK_CERT_STATE TAK_CERT_CITY TAK_CERT_ORG TAK_CERT_OU TAK_CERT_PASS; do
    [ -n "${!var:-}" ] || die "Required variable '$var' is not set."
    # Enforce UPPERCASE letters, digits, hyphens only (same rule as interactive script)
    if [[ ! "${!var}" =~ ^[A-Z0-9-]+$ ]]; then
        die "$var must be UPPERCASE letters, digits, and hyphens only. Got: ${!var}"
    fi
done

ca_name="${TAK_CERT_CA_NAME:-TAK-CA}"
info "State:  ${TAK_CERT_STATE}"
info "City:   ${TAK_CERT_CITY}"
info "Org:    ${TAK_CERT_ORG}"
info "OU:     ${TAK_CERT_OU}"
info "CA:     ${ca_name}"

# ── Clean existing certs ──────────────────────────────────────────────────────
info "Removing any existing certificate files..."
rm -rf "${CERTS_DIR}/files"

# ── Patch cert-metadata.sh ────────────────────────────────────────────────────
info "Patching cert-metadata.sh with certificate metadata..."
cd "$CERTS_DIR"

# Helper: escape value for sed replacement field (handles \, |, &)
sed_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\&/g'; }

# The default cert-metadata.sh uses shell-variable expansion placeholders.
# We replace each placeholder with the literal value.
sed -i "s|STATE=\${STATE}|STATE=$(sed_escape "$TAK_CERT_STATE")|g" cert-metadata.sh
grep -q "STATE=$TAK_CERT_STATE" cert-metadata.sh \
    || die "Failed to patch STATE in cert-metadata.sh"

sed -i "s|CITY=\${CITY}|CITY=$(sed_escape "$TAK_CERT_CITY")|g" cert-metadata.sh
grep -q "CITY=$TAK_CERT_CITY" cert-metadata.sh \
    || die "Failed to patch CITY in cert-metadata.sh"

sed -i "s|ORGANIZATION=\${ORGANIZATION:-TAK}|ORGANIZATION=$(sed_escape "$TAK_CERT_ORG")|g" cert-metadata.sh
grep -q "ORGANIZATION=$TAK_CERT_ORG" cert-metadata.sh \
    || die "Failed to patch ORGANIZATION in cert-metadata.sh"

sed -i "s|ORGANIZATIONAL_UNIT=\${ORGANIZATIONAL_UNIT}|ORGANIZATIONAL_UNIT=$(sed_escape "$TAK_CERT_OU")|g" cert-metadata.sh
grep -q "ORGANIZATIONAL_UNIT=$TAK_CERT_OU" cert-metadata.sh \
    || die "Failed to patch ORGANIZATIONAL_UNIT in cert-metadata.sh"

info "cert-metadata.sh patched successfully."

# ── Generate certificates as the tak user ─────────────────────────────────────
info "Generating Root CA, Intermediate CA, server cert, admin cert, and sample user cert..."
export TAK_CA_NAME="$ca_name"

# makeCert.sh and makeRootCa.sh must be run from within $CERTS_DIR as the tak user.
# In Docker we are running as root, so we use su/runuser.
# TAK_CA_NAME is exported so makeRootCa.sh reads it non-interactively.
runuser -u tak -- bash -c "
    set -euo pipefail
    cd ${CERTS_DIR}
    export TAK_CA_NAME='${ca_name}'
    echo '${ca_name}' | ./makeRootCa.sh
    ./makeCert.sh ca intermediate-ca <<< 'Y'
    ./makeCert.sh server takserver
    ./makeCert.sh client admin
    ./makeCert.sh client user
"
info "Certificate generation complete."

# ── Patch CoreConfig.xml — X509 input ─────────────────────────────────────────
info "Configuring X509 client authentication on port 8089..."
sed -i \
    's|<input auth="anonymous" _name="stdtcp" protocol="tcp" port="8087"/>|<input auth="x509" _name="stdssl" protocol="tls" port="8089"/>|g' \
    /opt/tak/CoreConfig.xml
grep -q 'auth="x509"' /opt/tak/CoreConfig.xml \
    || die "Failed to configure X509 input in CoreConfig.xml"

# ── Patch CoreConfig.xml — intermediate CA truststore ─────────────────────────
info "Switching CoreConfig.xml to use intermediate CA truststore..."
sed -i \
    's|truststoreFile="certs/files/truststore-root.jks|truststoreFile="certs/files/truststore-intermediate-ca.jks|g' \
    /opt/tak/CoreConfig.xml
grep -q 'truststore-intermediate-ca.jks' /opt/tak/CoreConfig.xml \
    || die "Failed to configure intermediate CA truststore in CoreConfig.xml"

# ── Patch CoreConfig.xml — certificate signing ────────────────────────────────
info "Enabling TAK Server certificate signing (enrolled certs valid 30 days)..."

# Escape the password for use in a sed replacement string
escaped_pass="$(printf '%s' "$TAK_CERT_PASS" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\&/g')"

sed -i "s|<vbm enabled=\"false\"/>|<certificateSigning CA=\"TAKServer\"><certificateConfig>\\n<nameEntries>\\n<nameEntry name=\"O\" value=\"TAK\"/>\\n<nameEntry name=\"OU\" value=\"TAK\"/>\\n</nameEntries>\\n</certificateConfig>\\n<TAKServerCAConfig keystore=\"JKS\" keystoreFile=\"certs/files/intermediate-ca-signing.jks\" keystorePass=\"${escaped_pass}\" validityDays=\"30\" signatureAlg=\"SHA256WithRSA\" />\\n</certificateSigning>\\n <vbm enabled=\"false\"/>|g" \
    /opt/tak/CoreConfig.xml

grep -q 'keystorePass=' /opt/tak/CoreConfig.xml \
    || die "Certificate signing block was not written to CoreConfig.xml. Is <vbm enabled=\"false\"/> present?"

# ── Patch CoreConfig.xml — group cache ────────────────────────────────────────
sed -i 's|<auth>|<auth x509useGroupCache="true">|g' /opt/tak/CoreConfig.xml

info "CoreConfig.xml certificate configuration complete."
info "======================================"
info " TAK Server certs generated OK"
info " Admin .p12: /opt/tak/certs/files/admin.p12"
info "======================================"
