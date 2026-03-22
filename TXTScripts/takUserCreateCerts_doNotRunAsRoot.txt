#!/bin/bash

# Ryan Schilder - April 2023 (updated March 2026)
#
# Creates TAK Server root CA, intermediate CA, server cert, admin cert, and a
# sample user cert. Called by createTakCerts.sh as the 'tak' user.
#
# The root CA name is read from the TAK_CA_NAME environment variable (set by
# createTakCerts.sh). If not set, the user is prompted interactively.

set -euo pipefail

echo "Running as TAK user"

# Determine CA name — prefer env variable set by parent script, fall back to prompt
if [ -n "${TAK_CA_NAME:-}" ]; then
    echo "Using root CA name from environment: $TAK_CA_NAME"
    echo "creating Root CA"
    echo "$TAK_CA_NAME" | ./makeRootCa.sh
else
    echo "creating Root CA - enter CA name when prompted"
    ./makeRootCa.sh
fi

echo "creating Intermediate CA for signing"
echo "Answer Y when prompted"
./makeCert.sh ca intermediate-ca

echo "Make server ceftificate"
./makeCert.sh server takserver

echo "Make admin certificate"
./makeCert.sh client admin

echo "Make user certificate"
./makeCert.sh client user

##end of script
