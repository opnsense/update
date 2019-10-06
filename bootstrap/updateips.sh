#!/bin/sh

#
# Output usage messsage.
#

if [ "$#" -ne 6 ]; then
    echo " "
    echo " Illegal number of parameters"
    echo " "
    echo " "
    echo " Usage: updateips.sh wanip wansubnet-cidr lanip lansubnet-cidr langw-ip wangw-ip"
    echo " "
    echo " For Example: "
    echo " "
    echo " If the IPs, subnet cidr and gw ips are:"
    echo " WAN IP: 192.168.0.7"
    echo " WAN SUBNET CIDR: /22"
    echo " LAN IP: 192.168.4.7"
    echo " LAN SUBNET CIDR: /22"
    echo " LAN GW IP: 192.168.4.1"
    echo " WAN GW IP: 192.168.0.1"
    echo " "
    echo " Then the script would be run as: "
    echo " "
    echo " /bin/sh updateips.sh 192.168.0.7 22 192.168.4.7 22 192.168.4.1 192.168.0.1"
    echo " "
    exit 1 
else

echo " sed -i'.backup.1' -e 's/1.1.1.1/$1/g' config.xml "
sed -i'.backup.1' -e 's/1.1.1.1/$1/g' config.xml

echo " sed -i'.backup.2' -e 's/2.2.2.2/$2/g' config.xml "
sed -i'.backup.2' -e 's/2.2.2.2/$2/g' config.xml

echo " sed -i'.backup.3' -e 's/3.3.3.3/$3/g' config.xml "
sed -i'.backup.3' -e 's/3.3.3.3/$3/g' config.xml

echo " sed -i'.backup.4' -e 's/4.4.4.4/$4/g' config.xml "
sed -i'.backup.4' -e 's/4.4.4.4/$4/g' config.xml

echo " sed -i'.backup.5' -e 's/5.5.5.5/$5/g' config.xml "
sed -i'.backup.5' -e 's/5.5.5.5/$5/g' config.xml

echo " sed -i'.backup.6' -e 's/6.6.6.6/$6/g' config.xml "
sed -i'.backup.6' -e 's/6.6.6.6/$6/g' config.xml


fi
