# DigitalTAK – TAK Server 5.7 Docker Image
# Base: eclipse-temurin:17-jammy (matches the official tak.gov Docker release)
#
# Build prerequisites:
#   The official takserver-docker-5.7-RELEASE-8 package must be extracted to
#   takserver-docker-5.7-RELEASE-8/ in the repo root (sibling to docker/).
#   Download from https://tak.gov (free account required).
#
# Build context: repo root (..)
#   docker compose sets context: .. so COPY paths below resolve from the repo root.

FROM eclipse-temurin:17-jammy

RUN apt-get update && \
    apt-get install -y net-tools netcat vim && \
    rm -rf /var/lib/apt/lists/*

# ── TAK Server application files (from official Docker release package) ───────
COPY takserver-docker-5.7-RELEASE-8/tak/ /opt/tak/

RUN find /opt/tak -name "*.sh" -exec chmod +x {} \; && \
    # Seed CoreConfig.xml from the example; entrypoint patches the DB password
    cp /opt/tak/CoreConfig.example.xml /opt/tak/CoreConfig.xml && \
    mkdir -p /opt/tak/logs /opt/tak/certs/files

# ── Entrypoint wrapper ────────────────────────────────────────────────────────
COPY docker/scripts/entrypoint.sh  /opt/tak/docker/entrypoint.sh
COPY docker/scripts/init-certs.sh  /opt/tak/docker/init-certs.sh
COPY docker/scripts/healthcheck.sh /opt/tak/docker/healthcheck.sh
RUN sed -i 's/\r//' /opt/tak/docker/*.sh && chmod +x /opt/tak/docker/*.sh

# ── Runtime ports ─────────────────────────────────────────────────────────────
# 8089  - TAK CoT clients (TLS)
# 8443  - WebTAK / REST API / Admin console (HTTPS)
# 8446  - Certificate enrollment (HTTPS)
EXPOSE 8089 8443 8446

ENTRYPOINT ["/opt/tak/docker/entrypoint.sh"]
