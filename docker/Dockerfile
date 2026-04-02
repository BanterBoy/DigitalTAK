# DigitalTAK – TAK Server 5.7 Docker Image
# Base: Rocky Linux 9 (matches bare-metal target platform)
#
# Build prerequisites:
#   Place takserver-5.7-RELEASE8.noarch.rpm (and optionally takserver-public-gpg.key)
#   in this docker/ directory before running `docker compose build`.
#   Download from https://tak.gov (free account required).
#
# Build args:
#   TAK_RPM          Filename of the TAK Server RPM (default: takserver-5.7-RELEASE8.noarch.rpm)
#   TAK_GPG_KEY      Filename of the TAK Server GPG key for RPM signature verification
#                    (optional; set to empty string "" to skip verification)

FROM rockylinux:9

ARG TAK_RPM=takserver-5.7-RELEASE8.noarch.rpm
ARG TAK_GPG_KEY=takserver-public-gpg.key

# ── System dependencies ────────────────────────────────────────────────────────
RUN dnf install -y dnf-plugins-core epel-release && \
    dnf config-manager --set-enabled crb && \
    # Add PostgreSQL 16 repo (client tools needed by TAK Server RPM dependencies)
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y \
        java-17-openjdk-devel \
        openssl \
        checkpolicy \
        curl \
        xmlstarlet \
        procps-ng \
        net-tools \
        postgresql16 && \
    dnf clean all

# ── Create TAK system users (normally done by RPM postinstall scripts) ────────
# We pre-create them so --noscripts install doesn't break permissions later.
RUN groupadd -r tak 2>/dev/null || true && \
    useradd -r -g tak -s /sbin/nologin -d /opt/tak tak 2>/dev/null || true && \
    groupadd -r atak 2>/dev/null || true && \
    useradd -r -g atak -s /bin/bash -d /home/atak -m atak 2>/dev/null || true

# ── Install TAK Server RPM ─────────────────────────────────────────────────────
# Copy RPM (and optional GPG key) from build context
COPY ${TAK_RPM} /tmp/takserver.rpm

# GPG verification (conditional — skipped if key file is not present)
RUN if [ -n "${TAK_GPG_KEY}" ] && [ -f "/tmp/${TAK_GPG_KEY}" ]; then \
        rpm --import /tmp/${TAK_GPG_KEY} && \
        rpm --checksig /tmp/takserver.rpm && \
        echo "GPG signature verified OK"; \
    else \
        echo "WARNING: Skipping GPG verification (key not provided in build context)"; \
    fi

# Install without running pre/postinstall scripts that require a live DB and systemd.
# All initialisation is handled at container startup by entrypoint.sh instead.
RUN rpm -ivh --noscripts /tmp/takserver.rpm && rm -f /tmp/takserver.rpm

# ── Apply SELinux policy (no-op in most container runtimes) ───────────────────
RUN cd /opt/tak && ./apply-selinux.sh 2>/dev/null || \
    echo "INFO: apply-selinux.sh skipped (SELinux not available in container context)"

# ── Fix ownership that postinstall would have set ─────────────────────────────
RUN chown -R tak:tak /opt/tak && \
    chmod 755 /opt/tak && \
    # Cert scripts need to be executable
    find /opt/tak/certs -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# ── Copy container scripts ────────────────────────────────────────────────────
COPY scripts/entrypoint.sh    /opt/tak/docker/entrypoint.sh
COPY scripts/cert-gen.sh      /opt/tak/docker/cert-gen.sh
COPY scripts/configure-db.sh  /opt/tak/docker/configure-db.sh
COPY scripts/init-groups.sh   /opt/tak/docker/init-groups.sh
COPY scripts/healthcheck.sh   /opt/tak/docker/healthcheck.sh

RUN chmod +x /opt/tak/docker/*.sh

# ── Runtime ports ─────────────────────────────────────────────────────────────
# 8089  - TAK CoT clients (TLS)
# 8443  - WebTAK / REST API / Admin console (HTTPS)
# 8446  - Certificate enrollment (HTTPS)
EXPOSE 8089 8443 8446

ENTRYPOINT ["/opt/tak/docker/entrypoint.sh"]
