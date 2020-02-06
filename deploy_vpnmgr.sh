#!/usr/bin/env bash

# Name:         deploy_openvpn.sh
# Description:  Deploy and setup openvpn server and management scripts
# OS:           CentOS 7
# Author:        <Dmitry V.> dmitry.vlasov@fastmail.com

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "---------- Variables ----------"
addr=$(curl ifconfig.me)
echo ""
port=$(awk -v min=35000 -v max=65535 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')

echo "---------- Install packages ----------"
yum install -y epel-release
yum install -y zip unzip wget openvpn firewalld
systemctl enable firewalld
systemctl start firewalld

echo "---------- Download and placement EasyRSA ----------"
wget https://github.com/OpenVPN/easy-rsa/archive/master.zip

unzip -qq master.zip 'easy-rsa-master/easyrsa3/*' -d /etc/openvpn/ca/
unzip -qq master.zip 'easy-rsa-master/easyrsa3/*' -d /etc/openvpn/pki/

mv /etc/openvpn/ca/easy-rsa-master/easyrsa3/* /etc/openvpn/ca/
mv /etc/openvpn/pki/easy-rsa-master/easyrsa3/* /etc/openvpn/pki/

rm -rf /etc/openvpn/ca/easy-rsa-master
rm -rf /etc/openvpn/pki/easy-rsa-master
rm ~/master.zip

echo "---------- Create CA ----------"
cd /etc/openvpn/ca
./easyrsa init-pki
./easyrsa build-ca nopass <<< "
"
echo "---------- Generate CRL ----------"
./easyrsa gen-crl
cp /etc/openvpn/ca/pki/crl.pem /etc/openvpn/server/crl.pem

echo "---------- Create PKI ----------"
cd /etc/openvpn/pki
./easyrsa init-pki
./easyrsa gen-req server nopass <<< "
"
./easyrsa
./easyrsa

echo "---------- Sign server certificate ----------"
cd /etc/openvpn/ca
./easyrsa import-req /etc/openvpn/pki/pki/reqs/server.req server
./easyrsa sign-req server server <<< "yes
"

echo "---------- Create DH key ----------"
cd /etc/openvpn/pki
./easyrsa gen-dh
cp /etc/openvpn/pki/pki/dh.pem /etc/openvpn/ca/pki/dh.pem

echo "---------- OpenVPN setup ----------"
rm -rf /etc/openvpn/client/
openvpn --genkey --secret /etc/openvpn/server/ta.key

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.proxy_ndp = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.use_tempaddr = 3" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.use_tempaddr = 3" >> /etc/sysctl.conf
sysctl -p

mkdir /etc/openvpn/client/
chown nobody:nobody /etc/openvpn/client/
touch /etc/openvpn/client/clients.db
chown nobody:nobody /etc/openvpn/client/clients.db
chcon -u system_u -t openvpn_etc_rw_t /etc/openvpn/client/clients.db

mkdir /etc/openvpn/clients/
chown openvpn:openvpn /etc/openvpn/clients/

if ! [[ "$(command -v firewall-cmd)" == "" ]]; then
    firewall-cmd --permanent --add-port "$port/udp"
    firewall-cmd --permanent --add-masquerade
    SHARK=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}')
    firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${SHARK} -j MASQUERADE
    firewall-cmd --direct --add-rule ipv6 filter FORWARD 0 -i tun0 -o eth0 -j ACCEPT
    firewall-cmd --reload
fi

mkdir /var/log/openvpn

echo "port                    $port
proto                   udp
dev                     tun
ca                      /etc/openvpn/ca/pki/ca.crt
cert                    /etc/openvpn/ca/pki/issued/server.crt
key                     /etc/openvpn/pki/pki/private/server.key
dh                      /etc/openvpn/ca/pki/dh.pem
crl-verify              /etc/openvpn/server/crl.pem
server                  10.8.0.0 255.255.255.0
server-ipv6             2001:0db8:ee00:abcd::/64
push                    'route-ipv6 ::/124'
push                    'route-metric 2000'
topology                subnet
client-to-client
ifconfig-pool-persist   /etc/openvpn/client/ipp.txt
client-config-dir       /etc/openvpn/clients/
script-security         2
client-connect          /etc/openvpn/client/connect.sh
client-disconnect       /etc/openvpn/client/disconnect.sh
push                    'redirect-gateway def1 bypass-dhcp'
push                    'redirect-gateway ipv6'
push                    'dhcp-option DNS 8.8.8.8'
push                    'dhcp-option DNS 8.8.4.4'
keepalive               10 120
tls-crypt               /etc/openvpn/server/ta.key 0
key-direction           0
cipher                  AES-256-GCM
auth                    SHA256
user                    nobody
group                   nobody
persist-key
status                  /var/log/openvpn/openvpn-status.log
log                     /var/log/openvpn/openvpn.log
log-append              /var/log/openvpn/openvpn.log
verb                    3
explicit-exit-notify    1" > /etc/openvpn/server.conf

echo "---------- User management script setup ----------"
touch /etc/openvpn/client/clients.db
echo "client
dev                     tun
proto                   udp
remote                  $addr $port
resolv-retry            infinite
nobind
persist-key
persist-tun
remote-cert-tls         server
cipher                  AES-256-GCM
auth                    SHA256
key-direction           1
verb                    3" > /etc/openvpn/client/base_configuration.conf

wget "https://raw.githubusercontent.com/Atari365/vpnmgr/master/vpnmgr"
mv vpnmgr /usr/bin/
chmod +x /usr/bin/vpnmgr

echo '#!/bin/bash

# Name:         connect.sh
# Description:  Actions when connecting a user
# OS:           CentOS 7
# Author:        <Dmitry V.> dmitry.vlasov@fastmail.com

sed -i "s/^$common_name,Down/$common_name,Up/g" /etc/openvpn/client/clients.db' > /etc/openvpn/client/connect.sh

echo '#!/bin/bash

# Name:         disconnect.sh
# Description:  Actions when disconnecting a user
# OS:           CentOS 7
# Author:        <Dmitry V.> dmitry.vlasov@fastmail.com

sed -i "s/^$common_name,Up/$common_name,Down/g" /etc/openvpn/client/clients.db' > /etc/openvpn/client/disconnect.sh

chmod 555 /etc/openvpn/client/connect.sh
chmod 555 /etc/openvpn/client/disconnect.sh

systemctl enable openvpn@server
systemctl start openvpn@server

echo "INSTALLED" > /etc/openvpn/server/check
echo "Address = $addr"
echo "port = $port"
echo "Installation complete. Use vpnmgr command to manage client configurations.
Your port is $port.
Your IP address is $addr. If the value is false, make changes to /etc/openvpn/client/base_configuration.conf before creating client configs.
Firewalld was also installed. If you are using a custom ssh port, add it using the following commands: 
    sudo firewall-cmd --permanent --add-port=[PORT]/tcp
    sudo firewall-cmd --reload"

