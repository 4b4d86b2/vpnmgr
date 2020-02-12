#!/usr/bin/env bash
#
# Name:         deploy_vpnmgr.sh
# Description:  Deploy and setup openvpn server and management scripts
# OS:           CentOS 7
# Author:       <Dmitry V.> dmitry.vlasov@fastmail.com
# Version:      0.3
# TODO:         Почистить вывод от лишнего. Сделать его красивым.
# TODO:         Разворачвать лишь vpnmgr и шаблон сервера. Перенести созданиие сервера в vpnmgr
# TODO:         Добавить поддержку Ubuntu

function error() {
    echo -e "Error: $1. Exiting..." && exit 1
}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "Script deploying vpnmgr"

username_default=$(id -un 1000)
addr_default=$(dig @resolver1.opendns.com ANY myip.opendns.com +short)
port_default=$(awk -v min=35000 -v max=65535 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
server_name_default="server"

read -p "Username [$username_default]:" username
#read -p "Server name [$server_name_default]:" server_name
read -p "External address [$addr_default]:" addr
read -p "OpenVPN Port [$port_default]:" port

username=${username:-$username_default}
#server_name=${server_name:-$server_name_default}
server_name=${server_name_default}
addr=${addr:-$addr_default}
port=${port:-$port_default}
ssh_port_str=$(grep -E "^Port|^#Port" /etc/ssh/sshd_config)
ssh_port_str_arr=(${ssh_port_str// / })
ssh_port=${ssh_port_str_arr[1]}

vpnmgr_path="$(pwd)/vpnmgr"
deploy_dir="/etc/openvpn/vpnmgr/${server_name}"

# Install packages
yum install -y epel-release
yum install -y zip unzip wget openvpn firewalld
systemctl enable firewalld
systemctl start firewalld

# Create dirs
mkdir -p ${deploy_dir}
mkdir ${deploy_dir}/server
mkdir ${deploy_dir}/ca
mkdir ${deploy_dir}/pki
mkdir ${deploy_dir}/client_configs

# Download and placement EasyRSA
wget https://github.com/OpenVPN/easy-rsa/archive/master.zip

unzip -qq master.zip 'easy-rsa-master/easyrsa3/*' -d ${deploy_dir}/ca/
unzip -qq master.zip 'easy-rsa-master/easyrsa3/*' -d ${deploy_dir}/pki/

mv ${deploy_dir}/ca/easy-rsa-master/easyrsa3/* ${deploy_dir}/ca/
mv ${deploy_dir}/pki/easy-rsa-master/easyrsa3/* ${deploy_dir}/pki/

rm -rf ${deploy_dir}/ca/easy-rsa-master
rm -rf ${deploy_dir}/pki/easy-rsa-master
rm ~/master.zip

# Create CA
cd ${deploy_dir}/ca
./easyrsa init-pki
./easyrsa build-ca nopass <<< "
"
# Generate CRL
./easyrsa gen-crl
cp ${deploy_dir}/ca/pki/crl.pem ${deploy_dir}/server/crl.pem

# Create PKI
cd ${deploy_dir}/pki
./easyrsa init-pki
./easyrsa gen-req server nopass <<< "
"

# Sign server certificate
cd ${deploy_dir}/ca
./easyrsa import-req ${deploy_dir}/pki/pki/reqs/server.req server
./easyrsa sign-req server server <<< "yes
"

# Create DH key
cd ${deploy_dir}/pki
./easyrsa gen-dh
cp ${deploy_dir}/pki/pki/dh.pem ${deploy_dir}/ca/pki/dh.pem

# OpenVPN setup
openvpn --genkey --secret ${deploy_dir}/server/ta.key

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.proxy_ndp = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.send_redirects = 0" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.use_tempaddr = 3" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.use_tempaddr = 3" >> /etc/sysctl.conf
sysctl -p

chown nobody:nobody ${deploy_dir}/server/
chown ${username}:${username} ${deploy_dir}/client_configs/

if ! [[ "$(command -v firewall-cmd)" == "" ]]; then
    firewall-cmd --permanent --add-port "$port/udp"
    firewall-cmd --permanent --add-port "$ssh_port/tcp"
    firewall-cmd --permanent --add-masquerade
    SHARK=$(ip route get 8.8.8.8 | awk 'NR==1 {print $(NF-2)}')
    firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${SHARK} -j MASQUERADE
    firewall-cmd --direct --add-rule ipv6 filter FORWARD 0 -i tun0 -o eth0 -j ACCEPT
    firewall-cmd --reload
fi

mkdir -p /var/log/vpnmgr/${server_name}

echo "port                    $port
proto                   udp
dev                     tun
ca                      ${deploy_dir}/ca/pki/ca.crt
cert                    ${deploy_dir}/ca/pki/issued/server.crt
key                     ${deploy_dir}/pki/pki/private/server.key
dh                      ${deploy_dir}/ca/pki/dh.pem
crl-verify              ${deploy_dir}/server/crl.pem
server                  10.8.0.0 255.255.255.0
server-ipv6             2001:0db8:ee00:abcd::/64
topology                subnet
client-to-client
ifconfig-pool-persist   ${deploy_dir}/server/ipp.txt
client-config-dir       ${deploy_dir}/client_configs/
script-security         2
client-connect          ${deploy_dir}/server/connect.sh
client-disconnect       ${deploy_dir}/server/disconnect.sh
push                    'redirect-gateway def1 bypass-dhcp'
push                    'redirect-gateway ipv6'
push                    'route-ipv6 ::/124'
push                    'route-metric 2000'
push                    'dhcp-option DNS 8.8.8.8'
push                    'dhcp-option DNS 8.8.4.4'
keepalive               10 120
tls-crypt               ${deploy_dir}/server/ta.key 0
key-direction           0
cipher                  AES-256-GCM
auth                    SHA256
user                    nobody
group                   nobody
persist-key
status                  ${deploy_dir}/server/openvpn-status.log
log                     /var/log/vpnmgr/${server_name}/openvpn.log
log-append              /var/log/vpnmgr/${server_name}/openvpn.log
verb                    3
explicit-exit-notify    1" > ${deploy_dir}/server.conf

ln -s ${deploy_dir}/server.conf /etc/openvpn/${server_name}_vpnmgr.conf

# User management script setup
touch ${deploy_dir}/server/clients.db
chown nobody:nobody ${deploy_dir}/server/clients.db
chcon -u system_u -t openvpn_etc_rw_t ${deploy_dir}/server/clients.db
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
verb                    3" > ${deploy_dir}/server/base_configuration.conf

cp ${vpnmgr_path} /usr/bin/
chmod +x /usr/bin/vpnmgr

echo '#!/bin/bash
#
# Name:         connect.sh
# Description:  Actions when connecting a user
# OS:           CentOS 7
# Author:        <Dmitry V.> dmitry.vlasov@fastmail.com

sed -i "s/^$common_name,Down/$common_name,Up/g" '${deploy_dir}/server/clients.db > ${deploy_dir}/server/connect.sh

echo '#!/bin/bash
#
# Name:         disconnect.sh
# Description:  Actions when disconnecting a user
# OS:           CentOS 7
# Author:        <Dmitry V.> dmitry.vlasov@fastmail.com

sed -i "s/^$common_name,Up/$common_name,Down/g" '${deploy_dir}/server/clients.db > ${deploy_dir}/server/disconnect.sh

chmod 555 ${deploy_dir}/server/connect.sh
chmod 555 ${deploy_dir}/server/disconnect.sh

systemctl enable openvpn@${server_name}_vpnmgr
systemctl start openvpn@${server_name}_vpnmgr

echo "INSTALLED" > ${deploy_dir}/server/check
echo "Installation complete. Use vpnmgr command to manage client configurations.
Your port is $port.
Your IP address is $addr. If the value is false, make changes to ${deploy_dir}/server/base_configuration.conf before creating client configs.
Firewalld was also installed. If you are using a custom ssh port, add it using the following commands: 
    sudo firewall-cmd --permanent --add-port=[PORT]/tcp
    sudo firewall-cmd --reload"

