#!/bin/bash
# DigitalTAK - TAK Server Certificate Generation Helper
#
# Run this inside the running takserver container to generate the CA chain
# and all required certificates using the official TAK cert scripts:
#
#   docker exec -it docker-takserver-1 /opt/tak/docker/init-certs.sh
#
# After certs are generated, promote the admin cert:
#   docker exec -it docker-takserver-1 \
#     bash -c 'cd /opt/tak && java -jar utils/UserManager.jar certmod -A certs/files/admin.pem'
#
# Then copy the admin cert to your host and import it into your browser:
#   docker cp docker-takserver-1:/opt/tak/certs/files/admin.p12 .
#
# Required env vars (already set in docker-compose.yml):
#   TAK_CERT_STATE, TAK_CERT_CITY, TAK_CERT_ORG, TAK_CERT_OU
#   TAK_CERT_CA_NAME (default: TAK-CA)
#   TAK_CERT_PASS    (default: atakatak)

set -euo pipefail

cd /opt/tak/certs

# Export the variables that cert-metadata.sh reads from the environment.
export STATE="${TAK_CERT_STATE:?TAK_CERT_STATE is required}"
export CITY="${TAK_CERT_CITY:?TAK_CERT_CITY is required}"
export ORGANIZATION="${TAK_CERT_ORG:?TAK_CERT_ORG is required}"
export ORGANIZATIONAL_UNIT="${TAK_CERT_OU:?TAK_CERT_OU is required}"
export CAPASS="${TAK_CERT_PASS:-atakatak}"

CA_NAME="${TAK_CERT_CA_NAME:-TAK-CA}"

echo "[CERTS] Generating Root CA: ${CA_NAME}"
./makeRootCa.sh --ca-name "${CA_NAME}"

echo "[CERTS] Generating TAK Server certificate"
./makeCert.sh server takserver

echo "[CERTS] Generating admin client certificate"
./makeCert.sh client admin

echo "[CERTS] Generating sample user certificate"
./makeCert.sh client user

echo "[CERTS] Done. Certificates are in /opt/tak/certs/files/"
echo "[CERTS] Next step -- promote admin:"
echo "  docker exec -it <container> bash -c 'cd /opt/tak && java -jar utils/UserManager.jar certmod -A certs/files/admin.pem'"
