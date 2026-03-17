#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Amazon Linux 2, Fedora, Oracle Linux 8, Arch Linux, Rocky Linux and AlmaLinux.
# https://github.com/angristan/openvpn-install

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

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 9 ]]; then
				echo "⚠️ Your version of Debian is not supported."
				echo ""
				echo "However, if you're using Debian >= 9 or unstable/testing, you can continue at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported."
				echo ""
				echo "However, if you're using Ubuntu >= 16.04 or beta, you can continue at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/fedora-release ]]; then
		OS="fedora"
	elif [[ -e /etc/centos-release ]]; then
		OS="centos"
	elif [[ -e /etc/redhat-release ]]; then
		OS="redhat"
	elif [[ -e /etc/arch-release ]]; then
		OS="arch"
	else
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Rocky Linux or Arch Linux system"
		exit 1
	fi
}

function initialCheck() {
	if ! isRoot; then
		echo "Sorry, you need to run this as root"
		exit 1
	fi
	if ! tunAvailable; then
		echo "TUN is not available"
		exit 1
	fi
}

function installOpenVPN() {
	# Determine if IPv6 is available
	IPV6_SUPPORT="n"
	if [[ $(ip -6 addr | grep -c "global") -ge 1 ]]; then
		IPV6_SUPPORT="y"
	fi

	# Get public IP and interface
	NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
	IP=$(curl -s https://api.ipify.org)

	# Ask for settings (Omiti o diálogo longo aqui para o código não ficar gigante, 
	# mas no seu script ele roda as perguntas de PORTA e PROTOCOLO)
	
	# [PROCESSO DE INSTALAÇÃO DE PACOTES E EASY-RSA CONTINUA AQUI]
	# ...

	# --- ABAIXO A PARTE QUE ALTERAMOS PARA O PADRÃO PRISMABOT ---
	
	# Início da escrita do server.conf
	echo "port 1194" > /etc/openvpn/server.conf
	echo "proto udp" >> /etc/openvpn/server.conf
	echo "dev tun" >> /etc/openvpn/server.conf
	echo "user nobody" >> /etc/openvpn/server.conf
	echo "group nobody" >> /etc/openvpn/server.conf
	echo "persist-key" >> /etc/openvpn/server.conf
	echo "persist-tun" >> /etc/openvpn/server.conf
	echo "keepalive 10 120" >> /etc/openvpn/server.conf
	echo "topology subnet" >> /etc/openvpn/server.conf
	echo "server 177.35.0.0 255.255.255.0" >> /etc/openvpn/server.conf
	echo "ifconfig-pool-persist ipp.txt" >> /etc/openvpn/server.conf
	echo "push \"topology subnet\"" >> /etc/openvpn/server.conf

	# --- BLOCO PRISMABOT / SPLIT TUNNEL ---
	# Comentamos o redirect-gateway para manter a internet local
	# echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf
	
	# Injetamos a rota específica para o PABX
	echo 'push "route 177.35.0.0 255.255.255.0"' >> /etc/openvpn/server.conf

	# DNS: Não damos push em DNS externo para não quebrar a navegação local
	# O script original tem um loop de DNS, nós apenas comentamos o push final dele
	# --- FIM DO BLOCO PRISMABOT ---

	# Configurações de Criptografia
	echo "cipher AES-256-CBC" >> /etc/openvpn/server.conf
	echo "auth SHA256" >> /etc/openvpn/server.conf
	echo "tls-auth ta.key 0" >> /etc/openvpn/server.conf

	# IPv6 Clean
	if [[ $IPV6_SUPPORT == 'y' ]]; then
		echo 'server-ipv6 fd42:42:42:42::/112' >> /etc/openvpn/server.conf
		echo 'tun-ipv6' >> /etc/openvpn/server.conf
		echo 'push tun-ipv6' >> /etc/openvpn/server.conf
	fi

	# Restart
	systemctl restart openvpn-server@server
}

function newClient() {
	# Mantém sua função original de criar certificados e o .ovpn
	echo "Gerando novo cliente..."
}

# [O RESTANTE DO SEU SCRIPT SEGUE ABAIXO IGUAL AO ORIGINAL]
# manageMenu, removeOpenVPN, etc.

initialCheck
checkOS

if [[ -e /etc/openvpn/server.conf ]]; then
	# Se já está instalado, ele cai no seu menu original (manageMenu)
	source /etc/openvpn/server.conf
	# manageMenu (Sua função original)
else
	installOpenVPN
fi
