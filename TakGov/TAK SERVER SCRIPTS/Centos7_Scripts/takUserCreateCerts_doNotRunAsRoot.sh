#!/bin/bash

//Ryan Schilder - April 2023

//This script should not be run on its own. This will be run as the 'tak' user from the main script


echo "Running as TAK user"

echo "creating Root CA - USER MUST ENTER CA NAME"
./makeRootCa.sh

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
