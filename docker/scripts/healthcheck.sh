#!/bin/bash
# DigitalTAK – TAK Server Container Health Check
#
# Exits 0 (healthy) when the TAK Server REST API returns a valid version response.
# Exits 1 (unhealthy) otherwise.
#
# Used by Docker Compose healthcheck and referenced in Dockerfile HEALTHCHECK.

set -euo pipefail

response=$(curl -sk --max-time 5 "https://localhost:8443/Marti/api/version" 2>/dev/null) || exit 1
echo "$response" | grep -q '"version"' || exit 1
exit 0
