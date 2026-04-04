#!/bin/bash
##This will install Tak V5.2r16 on Rocky Linux 8.9, create a Root CA and Intermediate (signing) CA, enable certificate enrollment, enable channels, and create an admin and user .p12 certificate
##The /opt/tak/certs/files/admin.p12 certificate needs to be installed into firefox/chrome as a user certificate in order to conenct to the WebGUI as an admin
## If using an online hosting provider (linode, Digital Ocean, ssdnode, etc...) you may have to configure your firewall in their web interface
## ensure tcp 8089, 8443, 8446, and 80 are allowed through the firewall. 80 is only needed if you plan to use LetsEncrypt certificates

##Ryan Schilder - March 2024
echo "Increase MAX connections"
echo -e "* soft nofile 32768\n* hard nofile 32768" | sudo tee --append /etc/security/limits.conf

echo "++++++++++++++++++++++++++++++++++++++++++"
#done

sudo dnf install vim -y

sudo dnf config-manager --set-enabled crb

echo "Install epel-release"
sudo dnf install epel-release -y
echo "Install epel-release complete"
#done

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL OPENSSL +++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

#sudo dnf install -y openssl openssl-devel
#done

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL POSTGRESQL ++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

sudo rpm --import https://download.postgresql.org/pub/repos/yum/keys/PGDG-RPM-GPG-KEY-RHEL

echo "Install Postgres"
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
#done
echo "++++++++++++++++++++++++++++++++++++++++++"

echo "Module Disable postgresql and dnf update"
sudo dnf -qy module disable postgresql && sudo dnf update -y
#done

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL JAVA 17 +++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

echo "Manual Install - JDK 17"
sudo dnf install java-17-openjdk-devel -y
echo "Installed JDK 17"
#done

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ ENABLE POWER TOOLS ++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

#sudo dnf config-manager --set-enabled powertools
#sudo dnf config-manager --set-enabled crb

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "Install Postgres Complete"


echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL TAK SERVER ++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

##Install TAK Server v4.10 rel 60
echo "Install TAK server v5.0 REL69"
#sudo dnf install takserver-4.10-RELEASE50.noarch.rpm -y
sudo dnf install takserver-5.4-RELEASE17.noarch.rpm -y
#done
echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL CHECKPOLICY +++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

sudo dnf install checkpolicy
#done

cd /opt/tak && sudo ./apply-selinux.sh && sudo semodule -l | grep takserver

echo "go back to previous directory, or cert script copy fails"
cd -

##check java version
echo "Check JAVA version, should be 17.x"
java -version

echo "choose the java 17.x (openjdk) option (3?)"
sudo alternatives --config java


##Configure Tak Server

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++CONFIGURE TAK SERVER +++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

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
sudo cp createTakCerts.sh /opt/tak/certs
sudo cp takUserCreateCerts_doNotRunAsRoot.sh /opt/tak/certs

##allow script execution
sudo chmod +x /opt/tak/certs/createTakCerts.sh
sudo chmod +x /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
sudo chmod +x takserver_createLECerts.sh
sudo chmod +x createTakCerts.sh
sudo chmod +x promoteAdmin.sh

echo "running certificate script"
cd /opt/tak/certs/
sudo ./createTakCerts.sh

cd -

echo "promoting certs to admin"
./promoteAdmin.sh


echo "+++++++++++++++ ALL DONE! ++++++++++++++++"
