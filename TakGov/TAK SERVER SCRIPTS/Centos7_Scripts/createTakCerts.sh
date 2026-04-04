#!/bin/bash

#Ryan Schilder - April 2023

#This script will prompt the user to create the server certificate, root ca, intermediate ca, certificate enrollment.

#change dir
echo "changing to certs directory"
cd /opt/tak/certs/

#chmod+x to script
chmod +x takUserCreateCerts_doNotRunAsRoot.sh

echo "deleting existing certs, if they exist"
sudo rm -vRf /opt/tak/certs/files


#edit cert metadata
#cert-metadata.sh

echo "The following will edit cert-metadata.sh to create the correct certificates"
echo "Please enter the following in CAPS, WITH NO SPACES!"

read -p 'STATE: ' statevar
read -p 'CITY: ' cityvar
read -p 'ORGANIZATION: ' orgvar
read -p 'ORGANIZATIONAL_UNIT: ' ouvar




#replace STATE
sed -i 's/STATE=${STATE}/STATE='"$statevar"'/g' cert-metadata.sh

#replace CITY
sed -i 's/CITY=${CITY}/CITY='"$cityvar"'/g' cert-metadata.sh

#replace ORG
sed -i 's/ORGANIZATION=${ORGANIZATION:-TAK}/ORGANIZATION='"$orgvar"'/g' cert-metadata.sh

#replace OU
sed -i 's/ORGANIZATIONAL_UNIT=${ORGANIZATIONAL_UNIT}/ORGANIZATIONAL_UNIT='"$ouvar"'/g' cert-metadata.sh

echo "Default CA password used"

echo "cert-metadata.sh updated"
echo "creating certificates"

#run script as tak user

echo "switching to TAK user, creating certificates"
sudo -u tak /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh

echo "restarting tak server"
sudo systemctl restart takserver


echo "configuring Client X509 certificate authentication on port 8089"

sed -i 's|<input auth="anonymous" _name="stdtcp" protocol="tcp" port="8087"/>|<input auth="x509" _name="stdssl" protocol="tls" port="8089"/>|g' /opt/tak/CoreConfig.xml
echo "complete"

echo "configuring intermediate ca for use"

sed -i 's|truststoreFile="certs/files/truststore-root.jks|truststoreFile="certs/files/truststore-intermediate-ca.jks|g' /opt/tak/CoreConfig.xml
echo "complete"

echo "enabling TAKserver signing, enrolled user certificates will be valid for 3650 days"

sed -i 's|<vbm enabled="false"/>|<certificateSigning CA="TAKServer"><certificateConfig>\n<nameEntries>\n<nameEntry name="O" value="TAK"/>\n<nameEntry name="OU" value="TAK"/>\n</nameEntries>\n</certificateConfig>\n<TAKServerCAConfig keystore="JKS" keystoreFile="certs/files/intermediate-ca-signing.jks"  keystorePass="atakatak" validityDays="3650" signatureAlg="SHA256WithRSA" />\n</certificateSigning>\n <vbm enabled="false"/>|g' /opt/tak/CoreConfig.xml

sed -i 's|<auth>|<auth x509useGroupCache="true">|g' /opt/tak/CoreConfig.xml

echo "restarting tak server"
sudo systemctl restart takserver

echo "sleeping for 90 seconds, otherwise promoting admin cert will fail"
sleep 10s
echo "80"
sleep 10s
echo "70"
sleep 10s
echo "60"
sleep 10s
echo "50"
sleep 10s
echo "40"
sleep 10s
echo "30"
sleep 10s
echo "20"
sleep 10s
echo "10"
sleep 10s

echo "promoting admin.pem to administrator"
sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/admin.pem

echo "restarting tak server"
sudo systemctl restart takserver

echo "--==TAK SERVER CERTIFICATE CREATION SUCCESSFUL==--"
