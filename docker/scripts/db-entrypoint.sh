#!/bin/bash
# DigitalTAK - TAK Database Container Entrypoint Wrapper
#
# Docker named volumes are created root:root at runtime.
# pg_ctl initdb runs as the postgres user and cannot write to a root-owned
# directory, so we fix ownership here before handing off to the official
# TAK DB init script (configureInDocker.sh).

set -e

# Fix data directory ownership so initdb can write to it.
mkdir -p /var/lib/postgresql/15/data
chown -R postgres:postgres /var/lib/postgresql/15

# Ensure the PostgreSQL socket directory exists and is postgres-owned.
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql

exec /opt/tak/db-utils/configureInDocker.sh "$@"
