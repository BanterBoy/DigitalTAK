#!/bin/bash
##This will install Tak V4.8 on CentOS 7, create a Root CA and Intermediate (signing) CA, enable certificate enrollment, enable channels, and create an admin and user .p12 certificate
##The /opt/tak/certs/files/admin.p12 certificate needs to be installed into firefox/chrome as a user certificate in order to conenct to the WebGUI as an admin

##Ryan Schilder - April 2023
echo "Increase MAX connections"
echo -e "* soft nofile 32768\n* hard nofile 32768" | sudo tee --append /etc/security/limits.conf > /dev/null

echo "Install epel-release"
sudo yum install epel-release -y
echo "Install epel-release complete"

echo "Install Postgres"
sudo yum install https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm -y
echo "Install Postgres Complete"

echo "Update Packages"
sudo yum update -y
echo "Update Complete"

##Install TAK Server v4.9 rel 9
echo "Install TAK server v4.9 REL9"
sudo yum install takserver-4.9-RELEASE9.noarch.rpm -y

##check java version
echo "Check JAVA version, should be 11.x"
java -version

echo "choose the java 11.x (openjdk) option (3?)"
sudo alternatives --config java

##configure db
echo "Configuring TAK database"
sudo /opt/tak/db-utils/takserver-setup-db.sh

echo "daemon-reload"
sudo systemctl daemon-reload

echo "start takserver service"
sudo systemctl start takserver

echo "enable takserver service"
sudo systemctl enable takserver

#configure firewall
#8089 = tls client traffic, 8443 - WebTAK, 8446 - certificate enrollment
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp
sudo firewall-cmd --reload

echo "Install Complete, creating tak certificates!!"

echo "copying certificate scripts to correct locations"
cp createTakCerts.sh /opt/tak/certs
cp takUserCreateCerts_doNotRunAsRoot.sh /opt/tak/certs

##allow script execution
sudo chmod +x /opt/tak/certs/createTakCerts.sh
sudo chmod +x /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
sudo chmod +x takserver_createLECerts.sh

echo "running certificate script"
sudo /opt/tak/certs/createTakCerts.sh
