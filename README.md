# Deploy
```bash
git clone https://github.com/Atari365/vpnmgr.git
cd vpnmgr
chmod +x deploy_vpnmgr.sh
sudo ./deploy_vpnmgr.sh
```
Important: Firewalld will be installed. If you use custom ssh port, add it to firewall, or you lose ssh.

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
