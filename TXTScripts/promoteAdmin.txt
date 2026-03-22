#!/bin/bash

echo "promoting admin.pem to administrator"
sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/admin.pem

echo "restarting tak server"
sudo systemctl restart takserver

echo "copying admin.p12 to /home/atak/"
sudo cp /opt/tak/certs/files/admin.p12 /home/atak/

echo "changing owner of /home/atak/admin.p12 to atak user"
sudo chown atak /home/atak/admin.p12

echo "+++++++++++++++++++++++++++++++++++++++++++++++"
echo "+++++++++++++ COMPLETE ++++++++++++++++++++++++"
echo "+++++++++++++++++++++++++++++++++++++++++++++++"
