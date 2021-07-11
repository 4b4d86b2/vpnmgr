# Deploy
```bash
sudo yum install epel-release git firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo yum update
sudo reboot

# After reboot
git clone https://github.com/4b4d86b2/vpnmgr.git
cd vpnmgr
chmod +x deploy_vpnmgr.sh
sudo ./deploy_vpnmgr.sh
```
In very start script will ask you to enter some variables, that it will use for install.  For lefting default value, just hit enter. But: Check your external IP address. If it doesn't match what your provider gave you, change it to the correct one. Also, if your provider use it's own firewall (like AWS), you should open OpenVPN port in this firewall too (You can see chosen OpenVPN Port in the begining of the script, and you can change it to another). For this instalation you should open UDP port, not TCP.

# How to use vpnmgr 
```text
Usage: vpnmgr command [options]
   Create and delete OpenVPN client configurations
   
   Commands:
       create       Create the client configuration
       delete       Delete the client configuration
       help         Show this message
       status       Show existing configurations and their status
       update       Update vpnmgr from github repo
       version      Show the version
   
   Options:
       vpnmgr (create|delete) name
           name     Client configuration name
   
       vpnmgr status [name]
           name     Client configuration name (if empty, show a list of configurations)
```

For example, to create new user config, execute `sudo vpnmgr create Name`
> use `sudo` with vpnmgr: `sudo vpnmgr ...`

# How to download user configs
You can use sftp. For downloading config, named User_config, execute:
```
sftp user@SERVER-IP
> get /etc/openvpn/vpnmgr/server/client_configs/User_config.ovpn
```

