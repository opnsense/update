Here is the modified config.xml for installing a single interface FW in Azure ( also known as a firewall on a stick ).
Follow these steps after you have spun up the FW in Azure: 

     # pkg install -y ca_root_nss
     # fetch https://raw.githubusercontent.com/wjwidener/update/master/bootstrap/opnsense-bootstrap.sh
     # fetch https://raw.githubusercontent.com/wjwidener/update/master/bootstrap/singleinterface/config.xml
     # sh ./opnsense-bootstrap.sh -y
     # cp config.xml /usr/local/etc/config.xml
     # reboot

This will install the FW and pickup the assigned private ip of VM's NIC. The FW will assign it to its LAN interface. 

The WebGUI will be accessible at: https://<NIC-IP> 

SSH is enabled on port 22 

The default boot up creds are:

    # U: root
    # PW: opnsense
