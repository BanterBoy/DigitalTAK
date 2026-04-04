#!/bin/bash

##Ryan Schilder - v002 - June 12 2023
##This script will create LetsEncrypt certificates for the takserver

##You MUST have a public IP address.
##You MUST have a domain with a DNS server
##You MUST have already created a 'A' record for the takserver, and pointed it at your public IP address

##If you don't have all of this, do NOT run this script. It will fail.


certNameVar="PUT_DOMAIN_HERE"

## Conduct a certificate renewal dry run to verify permissions and path
sudo certbot renew --force-renewal

######## Edit this line
#Create our PKCS12 certificate from our signed certificate and private key
sudo openssl pkcs12 -export -in /etc/letsencrypt/live/$certNameVar/fullchain.pem -inkey /etc/letsencrypt/live/$certNameVar/privkey.pem -out takserver-le.p12 -name $certNameVar -password pass:atakatak

#View our PKCS12 content
#sudo openssl pkcs12 -info -in takserver-le.p12

#Create our Java Keystore from our PKCS12 certificate
sudo keytool -importkeystore -srcstorepass atakatak -deststorepass atakatak -destkeystore takserver-le.jks -srckeystore takserver-le.p12 -srcstoretype pkcs12

#remove the old jks and p12 files
sudo rm /opt/tak/certs/files/takserver-le.jks
sudo rm /opt/tak/certs/files/takserver-le.p12

#Move the certificate to the TAK certificate directory
sudo mv takserver-le.jks /opt/tak/certs/files/
sudo mv takserver-le.p12 /opt/tak/certs/files/

#Restore our permissions to default
sudo chown -R tak:tak /opt/tak

#restart takserver
sudo systemctl stop takserver


sudo systemctl start takserver

echo "complete - wait a minute before checking"
