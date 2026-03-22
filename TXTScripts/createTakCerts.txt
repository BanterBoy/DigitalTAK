#!/bin/bash

# Ryan Schilder - April 2023 (updated March 2026)
#
# Creates TAK Server CA chain, server cert, and admin cert.
# Patches cert-metadata.sh and CoreConfig.xml, then restarts takserver.
#
# Run AFTER RL9_tak5.7r8_install.sh has completed successfully.
# Run as root or with sudo from /opt/tak/certs/.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"

# ── Change to TAK certs directory ──────────────────────────────────────────────
echo "Changing to TAK certs directory..."
cd /opt/tak/certs/

# ── Ensure helper scripts are executable ──────────────────────────────────────
chmod +x takUserCreateCerts_doNotRunAsRoot.sh
chmod +x promoteAdmin.sh

echo "Deleting existing certificates (if any)..."
sudo rm -vRf /opt/tak/certs/files

# ── Collect certificate metadata ──────────────────────────────────────────────
echo ""
echo "The following will edit cert-metadata.sh to create the correct certificates."
echo "Enter values in CAPS with NO SPACES (letters and digits only)."
echo ""

read -r -p 'STATE (e.g. VA): ' statevar
read -r -p 'CITY  (e.g. ARLINGTON): ' cityvar
read -r -p 'ORGANIZATION (e.g. MYORG): ' orgvar
read -r -p 'ORGANIZATIONAL_UNIT (e.g. MYUNIT): ' ouvar

# Validate cert fields — must be UPPERCASE letters and digits only
for field_name in statevar cityvar orgvar ouvar; do
    field_val="${!field_name}"
    if [[ ! "$field_val" =~ ^[A-Z0-9]+$ ]]; then
        echo "ERROR: $field_name must be UPPERCASE letters and digits only. Got: $field_val"
        exit 1
    fi
done

read -r -p 'Root CA Name [TAK-CA]: ' ca_name
ca_name="${ca_name:-TAK-CA}"

read -r -s -p 'TAK certificate keystore password: ' takCertPass
echo ""
if [ -z "$takCertPass" ]; then
    echo "Password cannot be empty."
    exit 1
fi

read -r -s -p 'Confirm TAK certificate keystore password: ' takCertPassConfirm
echo ""
if [ "$takCertPass" != "$takCertPassConfirm" ]; then
    echo "Passwords do not match."
    exit 1
fi


# ── Patch cert-metadata.sh ─────────────────────────────────────────────────────
echo "Patching cert-metadata.sh..."

sed -i 's/STATE=${STATE}/STATE='"$statevar"'/g' cert-metadata.sh
if ! grep -q "STATE=$statevar" cert-metadata.sh; then
    echo "ERROR: Failed to patch STATE in cert-metadata.sh. Is it already configured?"
    exit 1
fi

sed -i 's/CITY=${CITY}/CITY='"$cityvar"'/g' cert-metadata.sh
if ! grep -q "CITY=$cityvar" cert-metadata.sh; then
    echo "ERROR: Failed to patch CITY in cert-metadata.sh. Is it already configured?"
    exit 1
fi

sed -i 's/ORGANIZATION=${ORGANIZATION:-TAK}/ORGANIZATION='"$orgvar"'/g' cert-metadata.sh
if ! grep -q "ORGANIZATION=$orgvar" cert-metadata.sh; then
    echo "ERROR: Failed to patch ORGANIZATION in cert-metadata.sh. Is it already configured?"
    exit 1
fi

sed -i 's/ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}/ORGANIZATIONAL_UNIT='"$ouvar"'/g' cert-metadata.sh
if ! grep -q "ORGANIZATIONAL_UNIT=$ouvar" cert-metadata.sh; then
    echo "ERROR: Failed to patch ORGANIZATIONAL_UNIT in cert-metadata.sh. Is it already configured?"
    exit 1
fi

echo "cert-metadata.sh updated successfully."

# ── Create certificates (run as tak user) ────────────────────────────────────
echo "Creating certificates as the 'tak' user..."
export TAK_CA_NAME="$ca_name"
sudo -u tak -E /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh

echo "Certificate creation complete."

# ── First takserver restart (load new certs) ──────────────────────────────────
echo "Restarting takserver to load new certificates..."
sudo systemctl restart takserver
wait_for_service takserver 180

echo "configuring Client X509 certificate authentication on port 8089"

sed -i 's|<input auth="anonymous" _name="stdtcp" protocol="tcp" port="8087"/>|<input auth="x509" _name="stdssl" protocol="tls" port="8089"/>|g' /opt/tak/CoreConfig.xml
if ! grep -q 'auth="x509"' /opt/tak/CoreConfig.xml; then
    echo "ERROR: Failed to configure X509 input in CoreConfig.xml."
    exit 1
fi
echo "X509 input configured."

echo "configuring intermediate ca for use"

sed -i 's|truststoreFile="certs/files/truststore-root.jks|truststoreFile="certs/files/truststore-intermediate-ca.jks|g' /opt/tak/CoreConfig.xml
if ! grep -q 'truststore-intermediate-ca.jks' /opt/tak/CoreConfig.xml; then
    echo "ERROR: Failed to configure intermediate CA truststore in CoreConfig.xml."
    exit 1
fi
echo "Intermediate CA truststore configured."

echo "enabling TAKserver signing, enrolled user certificates will be valid for 30 days"

escapedTakCertPass="$(sed_replace_quote "$takCertPass")"
sed -i "s|<vbm enabled=\"false\"/>|<certificateSigning CA=\"TAKServer\"><certificateConfig>\\n<nameEntries>\\n<nameEntry name=\"O\" value=\"TAK\"/>\\n<nameEntry name=\"OU\" value=\"TAK\"/>\\n</nameEntries>\\n</certificateConfig>\\n<TAKServerCAConfig keystore=\"JKS\" keystoreFile=\"certs/files/intermediate-ca-signing.jks\" keystorePass=\"$escapedTakCertPass\" validityDays=\"30\" signatureAlg=\"SHA256WithRSA\" />\\n</certificateSigning>\\n <vbm enabled=\"false\"/>|g" /opt/tak/CoreConfig.xml
if ! grep -q 'keystorePass=' /opt/tak/CoreConfig.xml; then
	echo "ERROR: CoreConfig.xml certificate signing block was not written. Verify <vbm enabled=\"false\"/> is present in CoreConfig.xml."
	exit 1
fi

sed -i 's|<auth>|<auth x509useGroupCache="true">|g' /opt/tak/CoreConfig.xml

# ── Second takserver restart (apply CoreConfig changes) ──────────────────────
echo "Restarting takserver to apply CoreConfig.xml changes..."
sudo systemctl restart takserver
wait_for_service takserver 300

echo ""
echo "--==TAK SERVER CERTIFICATE CREATION SUCCESSFUL==--"
echo ""
echo "Next step: run promoteAdmin.sh to grant admin rights to the admin certificate."
