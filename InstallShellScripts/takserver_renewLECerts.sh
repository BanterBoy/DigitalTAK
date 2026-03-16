#!/bin/bash

##Ryan Schilder - v002 - June 12 2023
##This script will create LetsEncrypt certificates for the takserver

##You MUST have a public IP address.
##You MUST have a domain with a DNS server
##You MUST have already created a 'A' record for the takserver, and pointed it at your public IP address

##If you don't have all of this, do NOT run this script. It will fail.

set -euo pipefail


CERT_NAME="${1:-${CERT_NAME:-}}"

if [ -z "$CERT_NAME" ] && [ -f /etc/takserver_renew.conf ]; then
	# shellcheck disable=SC1091
	source /etc/takserver_renew.conf
	CERT_NAME="${CERT_NAME:-}"
fi

if [ -z "$CERT_NAME" ]; then
	echo "ERROR: Certificate name not provided."
	echo "Provide as arg: sudo ./takserver_renewLECerts.sh tak.example.com"
	echo "Or set CERT_NAME in /etc/takserver_renew.conf"
	exit 1
fi

LE_CERT_DIR="/etc/letsencrypt/live/$CERT_NAME"

if [ ! -f "$LE_CERT_DIR/fullchain.pem" ] || [ ! -f "$LE_CERT_DIR/privkey.pem" ]; then
	echo "ERROR: Missing Let's Encrypt files under $LE_CERT_DIR"
	exit 1
fi

## Renew certificates if needed
sudo certbot renew

######## Edit this line
#Create our PKCS12 certificate from our signed certificate and private key
sudo openssl pkcs12 -export -in "$LE_CERT_DIR/fullchain.pem" -inkey "$LE_CERT_DIR/privkey.pem" -out takserver-le.p12 -name "$CERT_NAME" -password pass:atakatak

#View our PKCS12 content
#sudo openssl pkcs12 -info -in takserver-le.p12

#Create our Java Keystore from our PKCS12 certificate
sudo keytool -importkeystore -srcstorepass atakatak -deststorepass atakatak -destkeystore takserver-le.jks -srckeystore takserver-le.p12 -srcstoretype pkcs12

#remove the old jks and p12 files
sudo rm -f /opt/tak/certs/files/takserver-le.jks
sudo rm -f /opt/tak/certs/files/takserver-le.p12

#Move the certificate to the TAK certificate directory
sudo mv takserver-le.jks /opt/tak/certs/files/
sudo mv takserver-le.p12 /opt/tak/certs/files/

#Restore our permissions to default
sudo chown -R tak:tak /opt/tak

#restart takserver
sudo systemctl stop takserver


sudo systemctl start takserver

echo "complete - wait a minute before checking"
