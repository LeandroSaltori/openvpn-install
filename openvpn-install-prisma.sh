#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Rocky Linux.
# Customizado para Prismabot - Split Tunneling (Acesso PABX + Internet Local)

function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function tunAvailable() {
	if [ ! -e /dev/net/tun ]; then
		return 1
	fi
}

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release
	elif [[ -e /etc/fedora-release ]]; then
		OS="fedora"
	elif [[ -e /etc/centos-release || -e /etc/redhat-release || -e /etc/rocky-release ]]; then
		OS="centos"
	else
		echo "Sistema operacional não suportado."
		exit 1
	fi
}

function initialCheck() {
	if ! isRoot; then
		echo "Você precisa rodar como root!"
		exit 1
	fi
	if ! tunAvailable; then
		echo "Dispositivo TUN não disponível!"
		exit 1
	fi
}

function installOpenVPN() {
	IP=$(curl -s https://api.ipify.org)
	PORT="1194"
	PROTOCOL="udp"

	if [[ $OS == 'debian' ]]; then
		apt-get update
		apt-get install -y openvpn openssl ca-certificates easy-rsa
	else
		yum install -y epel-release
		yum install -y openvpn openssl ca-certificates easy-rsa
	fi

	# Configuração do EASY-RSA e Certificados
	EASYRSA_DIR="/etc/openvpn/easy-rsa"
	mkdir -p $EASYRSA_DIR
	cp -r /usr/share/easy-rsa/* $EASYRSA_DIR/
	cd $EASYRSA_DIR || exit
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	./easyrsa --batch gen-req server nopass
	./easyrsa --batch sign-req server server
	./easyrsa --batch gen-dh
	openvpn --genkey --secret ta.key
	cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/

	# --- GERAÇÃO DO SERVER.CONF (PADRÃO PRISMABOT) ---
	cat <<EOF > /etc/openvpn/server.conf
port $PORT
proto $PROTOCOL
dev tun
user nobody
group nobody
persist-key
persist-tun
keepalive 10 120
topology subnet
server 177.35.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
cipher AES-256-CBC
auth SHA256
verb 3

# --- AJUSTES SPLIT TUNNEL PRISMABOT ---
# NÃO redirecionamos o gateway (Mantém internet local do cliente)
# push "redirect-gateway def1 bypass-dhcp"

# Forçamos a rota apenas para a rede do PABX/Servidor
push "route 177.35.0.0 255.255.255.0"

# DNS desativado no túnel para evitar falha de nomes (UOL, Google, etc)
# push "dhcp-option DNS 8.8.8.8"
EOF

	# Habilitar IP Forwarding
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn.conf
	sysctl --system

	# Firewall (Ajustado para Rocky/CentOS)
	if [[ $OS == 'centos' ]]; then
		firewall-cmd --add-service=openvpn --permanent
		firewall-cmd --add-masquerade --permanent
		firewall-cmd --reload
	fi

	systemctl enable openvpn-server@server
	systemctl restart openvpn-server@server
	echo "Instalação concluída!"
}

function newClient() {
	CLIENT=$1
	cd /etc/openvpn/easy-rsa || exit
	./easyrsa --batch build-client-full "$CLIENT" nopass
	
	# Gerar arquivo .ovpn
	cat <<EOF > ~/"$CLIENT".ovpn
client
dev tun
proto udp
remote $(curl -s https://api.ipify.org) 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
key-direction 1
verb 3
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/"$CLIENT".crt)
</cert>
<key>
$(cat /etc/openvpn/easy-rsa/pki/private/"$CLIENT".key)
</key>
<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
EOF
	echo "Arquivo de cliente criado em: ~/$CLIENT.ovpn"
}

# --- EXECUÇÃO ---
initialCheck
checkOS

if [[ -e /etc/openvpn/server.conf ]]; then
	echo "OpenVPN Prismabot já instalado."
	echo "1) Adicionar novo usuário"
	echo "2) Sair"
	read -rp "Opção: " opt
	if [[ $opt == "1" ]]; then
		read -rp "Nome do cliente: " CN
		newClient "$CN"
	fi
else
	installOpenVPN
fi
