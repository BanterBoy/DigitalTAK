#!/bin/bash
##This will install TAK Server on Rocky Linux 9.x, create a Root CA and Intermediate (signing) CA,
##enable certificate enrollment, enable channels, and create an admin and user .p12 certificate.
##The /opt/tak/certs/files/admin.p12 certificate needs to be installed into firefox/chrome as a user certificate in order to conenct to the WebGUI as an admin
## If using an online hosting provider (linode, Digital Ocean, ssdnode, etc...) you may have to configure your firewall in their web interface
## ensure tcp 8089, 8443, 8446, and 80 are allowed through the firewall. 80 is only needed if you plan to use LetsEncrypt certificates

##Ryan Schilder - March 2024
##Updated for TAK Server 5.7-RELEASE8 - March 2026
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "Increase MAX connections"
if ! sudo grep -qE '^\*\s+soft\s+nofile\s+32768$' /etc/security/limits.conf; then
	echo -e "* soft nofile 32768\n* hard nofile 32768" | sudo tee --append /etc/security/limits.conf >/dev/null
fi

echo "++++++++++++++++++++++++++++++++++++++++++"
#done

sudo dnf install -y dnf-plugins-core
sudo dnf install vim -y

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

echo "Install Postgres repository"
sudo dnf --disablerepo='*' -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
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
if ! java -version 2>&1 | grep -q '"17\.'; then
	echo "WARNING: Active Java is not version 17. Run: sudo alternatives --config java"
fi
#done

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ ENABLE POWER TOOLS (CRB) +++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++++"

#sudo dnf config-manager --set-enabled powertools  # Rocky Linux 8 / RHEL 8 only
sudo dnf config-manager --set-enabled crb

echo "++++++++++++++++++++++++++++++++++++++++++++"
echo "Install Postgres and Java Complete"


echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL TAK SERVER ++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

echo "Install TAK server v5.7 RELEASE8"
TAK_RPM="$SCRIPT_DIR/takserver-5.7-RELEASE8.noarch.rpm"
TAK_GPG_KEY="$SCRIPT_DIR/takserver-public-gpg.key"
if [ -f "$TAK_GPG_KEY" ] && [ -f "$TAK_RPM" ]; then
	echo "Importing TAK Server GPG key and verifying RPM signature..."
	sudo rpm --import "$TAK_GPG_KEY"
	rpm --checksig "$TAK_RPM" || { echo "ERROR: RPM signature verification failed"; exit 1; }
	echo "GPG signature verified OK"
else
	echo "WARNING: Skipping GPG verification (key or RPM not found in $SCRIPT_DIR)"
	echo "Download takserver-public-gpg.key from tak.gov to enable verification"
fi
if [ -f "$TAK_RPM" ]; then
	sudo dnf install -y "$TAK_RPM"
else
	sudo dnf install -y takserver-5.7-RELEASE8.noarch.rpm
fi
#done
echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

echo "++++++++++++++++++++++++++++++++++++++++++"
echo "++++++ INSTALL CHECKPOLICY +++++++++++++++"
echo "++++++++++++++++++++++++++++++++++++++++++"

sudo dnf install -y checkpolicy
#done

cd /opt/tak && sudo ./apply-selinux.sh && sudo semodule -l | grep takserver

echo "go back to previous directory, or cert script copy fails"
cd -

##check java version
echo "Check JAVA version, should be 17.x"
java -version


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

echo "++++++++++++++++++++++++++++++++++++++++++"

echo "++++++ INSTALL + START FIREWALLD +++++++++"

echo "++++++++++++++++++++++++++++++++++++++++++"

sudo dnf install -y firewalld

sudo systemctl enable --now firewalld


#configure firewall
#8089 = tls client traffic, 8443 - WebTAK, 8446 - certificate enrollment
sudo firewall-cmd --zone=public --permanent --add-port=8089/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8446/tcp
sudo firewall-cmd --reload

echo "Install Complete, creating tak certificates!!"

echo "copying certificate scripts to correct locations"
sudo cp "$SCRIPT_DIR/createTakCerts.sh" /opt/tak/certs
sudo cp "$SCRIPT_DIR/takUserCreateCerts_doNotRunAsRoot.sh" /opt/tak/certs

##allow script execution
sudo chmod +x /opt/tak/certs/createTakCerts.sh
sudo chmod +x /opt/tak/certs/takUserCreateCerts_doNotRunAsRoot.sh
sudo chmod +x "$SCRIPT_DIR/takserver_createLECerts.sh"
sudo chmod +x "$SCRIPT_DIR/createTakCerts.sh"
sudo chmod +x "$SCRIPT_DIR/promoteAdmin.sh"

echo "running certificate script"
cd /opt/tak/certs/
sudo ./createTakCerts.sh

cd -

echo "promoting certs to admin"
"$SCRIPT_DIR/promoteAdmin.sh"


echo "+++++++++++++++ ALL DONE! ++++++++++++++++"
