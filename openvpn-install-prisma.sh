#!/bin/bash
# ==============================================================================
# Script de Instalação e Gerenciamento do OpenVPN - Prisma PABX & Proxmox VE
# Baseado na estrutura validada do installer, otimizado e simplificado.
# ==============================================================================

# Impedir execução por usuário comum
if [[ "$EUID" -ne 0 ]]; then
	echo "⚠️ Erro: Este script deve ser executado como ROOT."
	exit 1
fi

# Verificar disponibilidade da interface TUN
if [[ ! -e /dev/net/tun ]]; then
	echo "⚠️ Erro: A interface TUN (/dev/net/tun) não está disponível."
	exit 1
fi

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
	elif [[ -e /etc/system-release ]]; then
		source /etc/os-release
		if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" || $ID == "rhel" ]]; then
			OS="centos"
		else
			OS="generic_el"
		fi
	else
		echo "Sistema operacional não suportado."
		exit 1
	fi
}

function resolvePublicIP() {
	local ip
	ip=$(curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null)
	if [[ -z $ip ]]; then
		ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)
	fi
	if [[ -z $ip ]]; then
		ip=$(ip route get 1.1.1.1 2>/dev/null | grep -Po '(?<=src )(\S+)')
	fi
	echo "$ip"
}

function getPublicNIC() {
	local nic
	nic=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
	echo "$nic"
}

function installOpenVPN() {
	checkOS

	echo "=================================================================="
	echo "        Instalação do Servidor OpenVPN - Prisma PABX & Proxmox    "
	echo "=================================================================="
	echo ""

	# Obter IP público ou domínio
	DETECTED_IP=$(resolvePublicIP)
	if [[ -z $DETECTED_IP ]]; then
		DETECTED_IP="127.0.0.1"
	fi

	read -rp "Endereço IP público ou Domínio [${DETECTED_IP}]: " ENDPOINT
	if [[ -z $ENDPOINT ]]; then
		ENDPOINT="$DETECTED_IP"
	fi
	ENDPOINT=$(echo "$ENDPOINT" | tr -d '[:space:]')

	# Porta do servidor
	read -rp "Porta do OpenVPN [1194]: " PORT
	if [[ -z $PORT ]]; then
		PORT="1194"
	fi
	PORT=$(echo "$PORT" | tr -d '[:space:]')
	until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
		read -rp "Porta inválida. Digite novamente [1-65535]: " PORT
		if [[ -z $PORT ]]; then
			PORT="1194"
		fi
		PORT=$(echo "$PORT" | tr -d '[:space:]')
	done

	# Protocolo
	echo ""
	echo "Selecione o protocolo:"
	echo "   1) UDP (Recomendado - mais rápido)"
	echo "   2) TCP"
	read -rp "Opção [1-2, padrão 1]: " PROTOCOL_CHOICE
	case $PROTOCOL_CHOICE in
	2) PROTOCOL="tcp" ;;
	*) PROTOCOL="udp" ;;
	esac

	# Subrede VPN
	echo ""
	read -rp "Subrede IP da VPN [177.35.0.0]: " VPN_SUBNET
	if [[ -z $VPN_SUBNET ]]; then
		VPN_SUBNET="177.35.0.0"
	fi
	VPN_SUBNET=$(echo "$VPN_SUBNET" | tr -d '[:space:]')

	read -rp "Máscara de Rede da VPN [255.255.255.0]: " VPN_NETMASK
	if [[ -z $VPN_NETMASK ]]; then
		VPN_NETMASK="255.255.255.0"
	fi
	VPN_NETMASK=$(echo "$VPN_NETMASK" | tr -d '[:space:]')

	# Nome do Primeiro Cliente
	echo ""
	read -rp "Nome do primeiro arquivo de cliente [.ovpn]: " CLIENT_NAME
	if [[ -z $CLIENT_NAME ]]; then
		CLIENT_NAME="suporte-prisma"
	fi
	CLIENT_NAME=$(echo "$CLIENT_NAME" | tr -cd 'a-zA-Z0-9_-')

	# Placa de rede principal
	NIC=$(getPublicNIC)
	if [[ -z $NIC ]]; then
		echo "⚠️ Erro: Não foi possível detectar a interface de rede principal."
		exit 1
	fi

	echo ""
	echo "Iniciando a instalação dos pacotes..."

	# Instalar pacotes de acordo com a distribuição
	if command -v apt-get >/dev/null 2>&1; then
		apt-get update
		apt-get install -y openvpn iptables openssl wget ca-certificates curl tar
	elif command -v dnf >/dev/null 2>&1; then
		dnf install -y epel-release
		dnf install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python-utils
	else
		yum install -y epel-release
		yum install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python*
	fi

	if grep -qs "^nogroup:" /etc/group; then
		NOGROUP=nogroup
	else
		NOGROUP=nobody
	fi

	# Limpar Easy-RSA antigo se existir
	rm -rf /etc/openvpn/easy-rsa/

	# Baixar Easy-RSA 3.1.7
	EASYRSA_VER="3.1.7"
	wget -O ~/easy-rsa.tgz "https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_VER}/EasyRSA-${EASYRSA_VER}.tgz" || {
		echo "⚠️ Falha ao baixar Easy-RSA."
		exit 1
	}
	mkdir -p /etc/openvpn/easy-rsa
	tar xzf ~/easy-rsa.tgz --strip-components=1 --no-same-owner --directory /etc/openvpn/easy-rsa
	rm -f ~/easy-rsa.tgz

	cd /etc/openvpn/easy-rsa/ || exit 1

	cat <<EOF >vars
set_var EASYRSA_ALGO ec
set_var EASYRSA_CURVE prime256v1
set_var EASYRSA_CA_EXPIRE 3650
set_var EASYRSA_CERT_EXPIRE 3650
set_var EASYRSA_CRL_DAYS 3650
EOF

	SERVER_CN="server_prisma_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)"
	SERVER_NAME="server"

	echo "$SERVER_NAME" >SERVER_NAME_GENERATED

	echo "Gerando Infraestrutura de Chaves Públicas (PKI)..."
	./easyrsa init-pki
	./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass
	./easyrsa --batch build-server-full "$SERVER_NAME" nopass
	./easyrsa gen-crl

	# Chave TLS-Crypt
	mkdir -p /etc/openvpn
	if [[ ! -s /etc/openvpn/tls-crypt.key ]]; then
		openvpn --genkey secret /etc/openvpn/tls-crypt.key >/dev/null 2>&1 || true
	fi

	# Copiar certificados
	cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" pki/crl.pem /etc/openvpn/
	chmod 644 /etc/openvpn/crl.pem /etc/openvpn/ca.crt "/etc/openvpn/$SERVER_NAME.crt" 2>/dev/null || true
	chmod 600 "/etc/openvpn/$SERVER_NAME.key" 2>/dev/null || true
	chmod 644 /etc/openvpn/tls-crypt.key 2>/dev/null || true

	mkdir -p /etc/openvpn/ccd
	mkdir -p /var/log/openvpn

	# Gerar server.conf
	cat <<EOF >/etc/openvpn/server.conf
port $PORT
proto $PROTOCOL
dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
server $VPN_SUBNET $VPN_NETMASK
ifconfig-pool-persist ipp.txt
push "route $VPN_SUBNET $VPN_NETMASK"
tls-crypt tls-crypt.key
crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
auth SHA256
cipher AES-256-GCM
ncp-ciphers AES-256-GCM:AES-128-GCM
tls-server
tls-version-min 1.2
client-config-dir /etc/openvpn/ccd
status /var/log/openvpn/status.log
verb 3
EOF

	# Espelhar para /etc/openvpn/server/ (compatibilidade RHEL/CentOS/Rocky)
	mkdir -p /etc/openvpn/server
	cp /etc/openvpn/server.conf /etc/openvpn/server/server.conf
	cp /etc/openvpn/tls-crypt.key /etc/openvpn/ca.crt /etc/openvpn/crl.pem "/etc/openvpn/$SERVER_NAME.crt" "/etc/openvpn/$SERVER_NAME.key" /etc/openvpn/server/ 2>/dev/null || true

	# IP Forwarding no Kernel
	echo "net.ipv4.ip_forward=1" >/etc/sysctl.d/99-openvpn.conf
	sysctl --system >/dev/null 2>&1

	# Ajustar SELinux se ativo
	if command -v sestatus >/dev/null 2>&1; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ $PORT != '1194' ]]; then
				semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT" 2>/dev/null || semanage port -m -t openvpn_port_t -p "$PROTOCOL" "$PORT"
			fi
		fi
	fi

	# Criar scripts de regras iptables (estrutura do FUNCIONANDO)
	mkdir -p /etc/iptables
	cat <<EOF >/etc/iptables/add-openvpn-rules.sh
#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s ${VPN_SUBNET}/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF

	cat <<EOF >/etc/iptables/rm-openvpn-rules.sh
#!/bin/sh
iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT
EOF

	chmod +x /etc/iptables/add-openvpn-rules.sh
	chmod +x /etc/iptables/rm-openvpn-rules.sh

	# Criar serviço systemd para iptables-openvpn
	cat <<EOF >/etc/systemd/system/iptables-openvpn.service
[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	systemctl enable iptables-openvpn
	systemctl start iptables-openvpn

	# Ajustar permissões para usuário nobody
	chown -R nobody:$NOGROUP /etc/openvpn /var/log/openvpn 2>/dev/null || true
	chmod -R 755 /etc/openvpn /var/log/openvpn 2>/dev/null || true
	mkdir -p /run/openvpn-server /run/openvpn

	# Habilitar e Iniciar Serviço OpenVPN no Systemd
	rm -f /etc/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn@.service
	systemctl daemon-reload

	if systemctl list-unit-files | grep -qs "openvpn-server@.service"; then
		systemctl enable openvpn-server@server --now
	elif systemctl list-unit-files | grep -qs "openvpn@.service"; then
		systemctl enable openvpn@server --now
	else
		systemctl enable openvpn --now 2>/dev/null || systemctl enable openvpn@server --now 2>/dev/null || systemctl enable openvpn-server@server --now
	fi

	# Modelo de Configuração do Cliente (.ovpn)
	cat <<EOF >/etc/openvpn/client-template.txt
client
dev tun
proto $PROTOCOL
remote $ENDPOINT $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name $SERVER_NAME name
auth SHA256
cipher AES-256-GCM
tls-client
tls-version-min 1.2
verb 3
EOF

	# Gerar o primeiro cliente
	CLIENT="$CLIENT_NAME"
	newClientInternal "$CLIENT"

	echo ""
	echo "=================================================================="
	echo "       Instalação do Servidor OpenVPN Concluída com Sucesso!      "
	echo "=================================================================="
	echo "Arquivo de conexão do cliente gerado em:"
	echo "  👉 $SAVED_OVPN_PATH"
	echo ""
	echo "Nota: O cliente utilizará o modo Split-Tunneling, mantendo acesso à"
	echo "sua internet local enquanto acessa a rede PABX/Proxmox na faixa ${VPN_SUBNET}/24."
	echo "=================================================================="
}

function newClientInternal() {
	local client_name="$1"
	cd /etc/openvpn/easy-rsa/ || exit 1

	./easyrsa --batch build-client-full "$client_name" nopass >/dev/null 2>&1

	local homeDir="/root"
	if [[ -n ${SUDO_USER} && ${SUDO_USER} != "root" ]]; then
		homeDir="/home/${SUDO_USER}"
	fi

	SAVED_OVPN_PATH="$homeDir/${client_name}.ovpn"

	if [[ ! -s /etc/openvpn/tls-crypt.key ]]; then
		openvpn --genkey secret /etc/openvpn/tls-crypt.key >/dev/null 2>&1 || true
	fi

	cp /etc/openvpn/client-template.txt "$SAVED_OVPN_PATH"
	{
		echo "<ca>"
		cat "/etc/openvpn/easy-rsa/pki/ca.crt"
		echo "</ca>"
		echo "<cert>"
		awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/easy-rsa/pki/issued/${client_name}.crt"
		echo "</cert>"
		echo "<key>"
		cat "/etc/openvpn/easy-rsa/pki/private/${client_name}.key"
		echo "</key>"
		if [[ -s /etc/openvpn/tls-crypt.key ]]; then
			echo "<tls-crypt>"
			cat /etc/openvpn/tls-crypt.key
			echo "</tls-crypt>"
		fi
	} >>"$SAVED_OVPN_PATH"
}

function newClient() {
	echo ""
	echo "--- Adicionar Novo Cliente VPN ---"
	read -rp "Nome do cliente (ex: suporte-notebook): " CLIENT
	CLIENT=$(echo "$CLIENT" | tr -cd 'a-zA-Z0-9_-')

	if [[ -z $CLIENT ]]; then
		echo "⚠️ Nome inválido."
		return
	fi

	if [[ -f "/etc/openvpn/easy-rsa/pki/issued/${CLIENT}.crt" ]]; then
		echo "⚠️ Já existe um cliente cadastrado com o nome '$CLIENT'."
		return
	fi

	newClientInternal "$CLIENT"
	echo "✅ Cliente '$CLIENT' criado com sucesso!"
	echo "📄 Arquivo salvo em: $SAVED_OVPN_PATH"
}

function revokeClient() {
	echo ""
	echo "--- Revogar Acesso de Cliente ---"
	NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		echo "Nenhum cliente ativo encontrado."
		return
	fi

	echo "Selecione o cliente que deseja revogar:"
	tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '

	read -rp "Número do cliente [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
	until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
		read -rp "Número inválido. Escolha [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
	done

	CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "${CLIENTNUMBER}p")

	cd /etc/openvpn/easy-rsa/ || exit 1
	./easyrsa --batch revoke "$CLIENT" >/dev/null 2>&1
	./easyrsa gen-crl >/dev/null 2>&1

	rm -f /etc/openvpn/crl.pem
	cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
	chmod 644 /etc/openvpn/crl.pem

	echo "✅ Certificado do cliente '$CLIENT' foi revogado com sucesso!"
}

function removeOpenVPN() {
	echo ""
	read -rp "Tem certeza que deseja remover o OpenVPN e todas as configurações? [y/N]: " REMOVE
	if [[ $REMOVE == 'y' || $REMOVE == 'Y' ]]; then
		echo "Parando serviços..."
		systemctl disable iptables-openvpn --now >/dev/null 2>&1
		systemctl disable openvpn-server@server --now >/dev/null 2>&1
		systemctl disable openvpn@server --now >/dev/null 2>&1
		systemctl disable openvpn --now >/dev/null 2>&1

		/etc/iptables/rm-openvpn-rules.sh >/dev/null 2>&1
		rm -f /etc/systemd/system/iptables-openvpn.service
		rm -rf /etc/iptables

		rm -f /etc/systemd/system/openvpn-server@.service
		rm -f /etc/systemd/system/openvpn\@.service
		systemctl daemon-reload

		rm -rf /etc/openvpn/
		rm -rf /var/log/openvpn

		echo "✅ OpenVPN removido com sucesso!"
	else
		echo "Operação cancelada."
	fi
}

if [[ "$1" == "--remove" || "$1" == "--uninstall" || "$1" == "-r" ]]; then
	removeOpenVPN
	exit 0
fi

if [[ -e /etc/openvpn/server.conf ]]; then
	while true; do
		echo ""
		echo "=================================================================="
		echo "       Gerenciamento OpenVPN Prisma PABX & Proxmox (Instalado)    "
		echo "=================================================================="
		echo "   1) Adicionar novo cliente (.ovpn)"
		echo "   2) Revogar acesso de um cliente"
		echo "   3) Desinstalar OpenVPN do servidor"
		echo "   4) Sair"
		echo "=================================================================="
		read -rp "Escolha uma opção [1-4]: " OPTION
		case $OPTION in
		1) newClient ;;
		2) revokeClient ;;
		3)
			removeOpenVPN
			exit 0
			;;
		4) exit 0 ;;
		*) echo "Opção inválida." ;;
		esac
	done
else
	installOpenVPN
fi
