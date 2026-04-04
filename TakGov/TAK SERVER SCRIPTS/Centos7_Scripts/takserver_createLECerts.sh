#!/bin/bash

##Ryan Schilder - v002 - June 12 2023
##This script will create LetsEncrypt certificates for the takserver

##You MUST have a public IP address.
##You MUST have a domain with a DNS server
##You MUST have already created a 'A' record for the takserver, and pointed it at your public IP address

##If you don't have all of this, do NOT run this script. It will fail.

## Install snapd
sudo yum install snapd -y

## Enable snapd
sudo systemctl enable --now snapd.socket

## Create the symbolic link for snap
sudo ln -s /var/lib/snapd/snap /snap

## Add 80/TCP to our public zone and make it permanent
#configure firewall
#8089 = tls client traffic, 8443 - WebTAK, 8446 - certificate enrollment
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp
sudo firewall-cmd --zone=public --permanent --add-port=80/tcp

## Reload the firewall to accept our changes
sudo firewall-cmd --reload

## View our firewall to verify the change
sudo firewall-cmd --list-all

##wait to avoid "error: too early for operation, device not yet seeded or device model not acknowledge
sudo systemctl restart snapd.seeded.service
snap wait system seed.loaded


## Using snapd install certbot
sudo snap install --classic certbot

## Create the symbolic links to certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

## must be on the correct server, with port 80 open, and DNS setup...

## Begin our certificate signing process for a standalone webserver
sudo certbot certonly --standalone

########Edit this next line
## Verify our newly signed certificate by viewing the contents

read -p 'Certificate Name (FQDN) [ex: tak.domain.com]: ' certNameVar

openssl x509 -text -in /etc/letsencrypt/live/$certNameVar/fullchain.pem -noout

## Conduct a certificate renewal dry run to verify permissions and path
sudo certbot renew --dry-run

######## Edit this line
## Create our PKCS12 certificate from our signed certificate and private key
sudo openssl pkcs12 -export -in /etc/letsencrypt/live/$certNameVar/fullchain.pem -inkey /etc/letsencrypt/live/$certNameVar/privkey.pem -out takserver-le.p12 -name $certNameVar -password pass:atakatak

## View our PKCS12 content
#sudo openssl pkcs12 -info -in takserver-le.p12

## Create our Java Keystore from our PKCS12 certificate
sudo keytool -importkeystore -srcstorepass atakatak -deststorepass atakatak -destkeystore takserver-le.jks -srckeystore takserver-le.p12 -srcstoretype pkcs12

## Move the certificate to the TAK certificate directory
sudo mv takserver-le.jks /opt/tak/certs/files

## Restore our permissions to default
sudo chown -R tak:tak /opt/tak


cd /opt/tak
sudo systemctl stop takserver

###use sed to replace the existing 8446 connector with 

sed -i 's|<connector port="8446" clientAuth="false" _name="cert_https"/>|<connector port="8446" clientAuth="false" _name="LetsEncrypt" keystore="JKS" keystoreFile="certs/files/takserver-le.jks" keystorePass="atakatak"/>|g' /opt/tak/CoreConfig.xml

rm CoreConfig.example.xml
cp CoreConfig.xml CoreConfig.example.xml

sudo systemctl start takserver

echo "complete - wait a minute before checking"

echo "let's make a monthly cron job to renew the LE cert"

echo "modifying the renew script for your domain entered previously"

sed -i 's/certNameVar="PUT_DOMAIN_HERE"/certNameVar='"$certNameVar"'/g' takserver_renewLECerts.sh

echo "modified."

#allow renewal script to be executed
sudo chmod +x /home/atak/Downloads/takserver_renewLECerts.sh
cp /home/atak/Downloads/takserver_renewLECerts.sh /etc/cron.monthly/
echo "copied to /etc/cron.monthly"
echo "the takserver LE certificate should be renewed monthly"
