#!/bin/bash

AUTO_INSTALL=y
APPROVE_INSTALL=y
APPROVE_IP=y
IPV6_SUPPORT=n
PORT_CHOICE=1
PROTOCOL_CHOICE=1
DNS=1
COMPRESSION_ENABLED=n
CUSTOMIZE_ENC=n
CLIENT=prisma
PASS=1
ENDPOINT=$(curl -s ifconfig.me)

# instalar dependências
dnf install -y epel-release
dnf install -y openvpn easy-rsa iptables wget curl

mkdir -p /etc/openvpn/easy-rsa
cd /etc/openvpn

# gerar PKI
cd /etc/openvpn
make-cadir easy-rsa
cd easy-rsa

./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa gen-dh
./easyrsa build-server-full server nopass
./easyrsa build-client-full $CLIENT nopass
./easyrsa gen-crl

cp pki/ca.crt /etc/openvpn
cp pki/private/server.key /etc/openvpn
cp pki/issued/server.crt /etc/openvpn
cp pki/dh.pem /etc/openvpn
cp pki/crl.pem /etc/openvpn

# gerar server.conf
cat <<EOF > /etc/openvpn/server.conf
port 1194
proto udp
dev tun

user nobody
group nobody
persist-key
persist-tun

topology subnet

server 177.35.0.0 255.255.255.0

keepalive 10 120

cipher AES-128-GCM
auth SHA256

ca ca.crt
cert server.crt
key server.key
dh dh.pem
crl-verify crl.pem

client-config-dir /etc/openvpn/ccd

status /var/log/openvpn-status.log
verb 3

# DNS
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"

# SPLIT TUNNEL
push "route 177.35.0.0 255.255.255.0"

EOF

mkdir -p /etc/openvpn/ccd

# habilitar forward
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf
sysctl --system

# regras firewall
NIC=$(ip route | grep default | awk '{print $5}')

cat <<EOF > /etc/iptables-openvpn.sh
iptables -t nat -A POSTROUTING -s 177.35.0.0/24 -o $NIC -j MASQUERADE
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT
EOF

chmod +x /etc/iptables-openvpn.sh
/etc/iptables-openvpn.sh

# iniciar openvpn
systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

# gerar client.ovpn
cat <<EOF > /root/$CLIENT.ovpn
client
dev tun
proto udp
remote $ENDPOINT 1194
resolv-retry infinite
nobind
persist-key
persist-tun

remote-cert-tls server

cipher AES-128-GCM
auth SHA256

verb 3

EOF

echo "<ca>" >> /root/$CLIENT.ovpn
cat /etc/openvpn/easy-rsa/pki/ca.crt >> /root/$CLIENT.ovpn
echo "</ca>" >> /root/$CLIENT.ovpn

echo "<cert>" >> /root/$CLIENT.ovpn
awk '/BEGIN/,/END CERTIFICATE/' /etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt >> /root/$CLIENT.ovpn
echo "</cert>" >> /root/$CLIENT.ovpn

echo "<key>" >> /root/$CLIENT.ovpn
cat /etc/openvpn/easy-rsa/pki/private/$CLIENT.key >> /root/$CLIENT.ovpn
echo "</key>" >> /root/$CLIENT.ovpn

echo ""
echo "VPN instalada com sucesso!"
echo ""
echo "Arquivo cliente:"
echo "/root/$CLIENT.ovpn"
