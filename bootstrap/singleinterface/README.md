Here is the modified config.xml for installing a single interface FW in Azure ( also known as a firewall on a stick ).

This will install the FW and pickup the assigned private ip of VM's NIC. The FW will assign it to its LAN interface. 

The WebGUI will be accessible at: https://<NIC-IP> 

SSH is enabled on port 22 

The default boot up creds are:

U: root 
PW: opnsense
