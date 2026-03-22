#!/bin/bash

##Ryan Schilder
##Promote a TAK user certificate to administrator and deploy admin.p12
##Run AFTER createTakCerts.sh has completed successfully.

set -euo pipefail

echo "Checking that the 'atak' system user exists..."
if ! id atak &>/dev/null; then
	echo "ERROR: User 'atak' does not exist. Run the TAK installer first."
	exit 1
fi

echo "promoting admin.pem to administrator"
sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/admin.pem

echo "restarting tak server"
sudo systemctl restart takserver

echo "preparing /home/atak/ directory"
sudo mkdir -p /home/atak
sudo chown atak:atak /home/atak

echo "copying admin.p12 to /home/atak/"
sudo cp /opt/tak/certs/files/admin.p12 /home/atak/

echo "setting ownership and permissions on admin.p12"
sudo chown atak:atak /home/atak/admin.p12
sudo chmod 640 /home/atak/admin.p12

echo "+++++++++++++++++++++++++++++++++++++++++++++++"
echo "+++++++++++++ COMPLETE ++++++++++++++++++++++++"
echo "+++++++++++++++++++++++++++++++++++++++++++++++"
