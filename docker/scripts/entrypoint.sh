#!/bin/bash
# DigitalTAK - TAK Server Container Entrypoint
#
# 1. Generates TLS certificates on first start (sentinel: takserver.jks).
# 2. Patches the DB password into CoreConfig.xml.
# 3. Hands off to the official TAK Server startup script (configureInDocker.sh).

set -e

# Auto-generate certificates on first start.
# The cert volume is empty on a fresh deployment, so we generate everything
# needed for TLS before the Java processes start.
if [ ! -f /opt/tak/certs/files/takserver.jks ]; then
    echo "[ENTRYPOINT] No certificates found -- generating now..."
    /opt/tak/docker/init-certs.sh
    echo "[ENTRYPOINT] Certificate generation complete."
fi

# Patch DB password and cert passwords into CoreConfig.xml.
if [ -n "${TAK_DB_PASSWORD:-}" ]; then
    sed -i "s|username=\"martiuser\" password=\"[^\"]*\"|username=\"martiuser\" password=\"${TAK_DB_PASSWORD}\"|g" \
        /opt/tak/CoreConfig.xml
fi
CERT_PASS="${TAK_CERT_PASS:-atakatak}"
sed -i "s|keystorePass=\"[^\"]*\"|keystorePass=\"${CERT_PASS}\"|g" /opt/tak/CoreConfig.xml
sed -i "s|truststorePass=\"[^\"]*\"|truststorePass=\"${CERT_PASS}\"|g" /opt/tak/CoreConfig.xml

# Hand off to the official startup script.
# The 'init' argument causes it to start all TAK processes and then run
# 'tail -f /dev/null' to keep the container alive (see configureInDocker.sh).
exec /bin/bash -c "/opt/tak/configureInDocker.sh init >> /opt/tak/logs/takserver.log 2>&1"