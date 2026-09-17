#!/bin/bash
# ==============================================================================
# OPENVPN PRISMA V2 - INSTALADOR & GERENCIADOR INTELIGENTE
# Otimizado para IPBX Issabel, Asterisk, Proxmox VE & Rocky Linux 8/9, CentOS 7, Debian, Ubuntu
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCESSO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; }
log_error()   { echo -e "${RED}[ERRO]${NC} $1"; }

# Função para leitura interativa compatível com curl | bash
tty_read() {
    if [ -e /dev/tty ]; then
        read "$@" </dev/tty
    else
        read "$@"
    fi
}

# 1. Checagem de Root
if [[ "$EUID" -ne 0 ]]; then
    log_error "Este script deve ser executado como ROOT."
    exit 1
fi

# 2. Checagem da Interface TUN
if [[ ! -e /dev/net/tun ]]; then
    log_error "A interface TUN (/dev/net/tun) não está disponível."
    echo ""
    echo "Dica para Proxmox VE (Container LXC):"
    echo "Adicione as seguintes linhas no arquivo de configuração do container no host Proxmox (/etc/pve/lxc/<ID>.conf):"
    echo "  lxc.cgroup2.devices.allow: c 10:200 rwm"
    echo "  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file"
    echo ""
    exit 1
fi

# 3. Detecção de Sistema Operacional
check_os() {
    if [[ -e /etc/debian_version ]]; then
        OS_FAMILY="debian"
    elif [[ -e /etc/system-release ]] || [[ -e /etc/redhat-release ]]; then
        OS_FAMILY="rhel"
    else
        log_error "Sistema operacional não suportado."
        exit 1
    fi
}

# 4. Detecção de IP Público
resolve_public_ip() {
    local ip
    ip=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || true)
    fi
    if [[ -z "$ip" ]]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -Po '(?<=src )(\S+)' || true)
    fi
    echo "$ip"
}

# 5. Detecção de Interface de Rede Principal
get_public_nic() {
    local nic
    nic=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
    echo "$nic"
}

# ==============================================================================
# INSTALAÇÃO DO SERVIDOR
# ==============================================================================
install_openvpn() {
    check_os

    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}          INSTALADOR OPENVPN PRISMA V2 - REDE & VOIP PERFEITO         ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Sem queda de internet, compatível com Proxmox, Issabel & Rocky Linux ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    DETECTED_IP=$(resolve_public_ip)
    [[ -z "$DETECTED_IP" ]] && DETECTED_IP="127.0.0.1"

    echo -ne "${WHITE}IP público ou Domínio DDNS do PBX [${GREEN}${DETECTED_IP}${WHITE}]: ${NC}"
    tty_read -r ENDPOINT
    ENDPOINT="${ENDPOINT:-$DETECTED_IP}"
    ENDPOINT=$(echo "$ENDPOINT" | tr -d '[:space:]')

    echo -ne "${WHITE}Porta do OpenVPN [${GREEN}1194${WHITE}]: ${NC}"
    tty_read -r PORT
    PORT="${PORT:-1194}"
    PORT=$(echo "$PORT" | tr -d '[:space:]')

    echo ""
    echo -e "${WHITE}Escolha o protocolo:${NC}"
    echo "  [1] UDP (Recomendado - Mais rápido e ideal para VoIP)"
    echo "  [2] TCP (Para redes restritivas com bloqueio de UDP)"
    echo -ne "${WHITE}Opção [1/2]: ${NC}"
    tty_read -r PROTO_CHOICE
    if [[ "$PROTO_CHOICE" == "2" ]]; then
        PROTOCOL="tcp"
    else
        PROTOCOL="udp"
    fi

    echo ""
    echo -ne "${WHITE}IP do Servidor VPN [${GREEN}177.35.0.1${WHITE}]: ${NC}"
    tty_read -r VPN_IP_INPUT
    VPN_IP_INPUT="${VPN_IP_INPUT:-177.35.0.1}"
    VPN_IP_INPUT=$(echo "$VPN_IP_INPUT" | tr -d '[:space:]')

    OCTETS=(${VPN_IP_INPUT//./ })
    if [[ ${#OCTETS[@]} -eq 4 ]]; then
        VPN_SUBNET="${OCTETS[0]}.${OCTETS[1]}.${OCTETS[2]}.0"
        SERVER_GATEWAY_IP="${OCTETS[0]}.${OCTETS[1]}.${OCTETS[2]}.1"
    else
        VPN_SUBNET="177.35.0.0"
        SERVER_GATEWAY_IP="177.35.0.1"
    fi
    VPN_NETMASK="255.255.255.0"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${WHITE}                 MODO DE ROTEAMENTO DE INTERNET                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC} [1] ${GREEN}Split-Tunneling (RECOMENDADO PARA TELEFONIA / RAMAIS)${NC}            ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     -> A internet do cliente NÃO cai e NÃO passa pelo PBX.           ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     -> Somente o tráfego do PBX (${VPN_SUBNET}/24) passa pela VPN.    ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}                                                                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} [2] ${CYAN}Full-Tunneling (Navegação Completa via VPN)${NC}                      ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     -> Toda a internet do cliente é roteada pelo PBX.                ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}     -> Usa NAT/Masquerade e DNS 1.1.1.1 / 8.8.8.8 para não travar.   ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo -ne "${WHITE}Escolha o modo de roteamento [1/2, padrão 1]: ${NC}"
    tty_read -r ROUTING_CHOICE
    ROUTING_CHOICE="${ROUTING_CHOICE:-1}"

    echo ""
    echo -ne "${WHITE}Nome do primeiro certificado de cliente [${GREEN}ramal-suporte${WHITE}]: ${NC}"
    tty_read -r CLIENT_NAME
    CLIENT_NAME="${CLIENT_NAME:-ramal-suporte}"
    CLIENT_NAME=$(echo "$CLIENT_NAME" | tr -cd 'a-zA-Z0-9_-')

    NIC=$(get_public_nic)
    if [[ -z "$NIC" ]]; then
        log_warn "Não foi possível detectar a interface padrão. Usando 'eth0'."
        NIC="eth0"
    fi
    log_info "Interface de rede externa detectada: $NIC"

    echo ""
    log_info "Instalando dependências do sistema..."
    if [[ "$OS_FAMILY" == "debian" ]]; then
        apt-get update -y
        apt-get install -y openvpn iptables openssl wget ca-certificates curl tar
    else
        if command -v dnf &>/dev/null; then
            dnf install -y epel-release 2>/dev/null || true
            dnf install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python-utils 2>/dev/null || true
        else
            yum install -y epel-release 2>/dev/null || true
            yum install -y openvpn iptables openssl wget ca-certificates curl tar policycoreutils-python* 2>/dev/null || true
        fi
    fi

    # Configuração de usuário/grupo do daemon
    if grep -qs "^nogroup:" /etc/group; then
        NOGROUP="nogroup"
    else
        NOGROUP="nobody"
    fi

    # Baixar e configurar Easy-RSA
    log_info "Configurando Easy-RSA 3.1..."
    rm -rf /etc/openvpn/easy-rsa
    mkdir -p /etc/openvpn/easy-rsa
    TMP_DIR="/tmp/easyrsa_tmp_$$"
    mkdir -p "$TMP_DIR"
    wget -qO "$TMP_DIR/easyrsa.tgz" "https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz" || \
    curl -sSL -o "$TMP_DIR/easyrsa.tgz" "https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz"
    tar -xzf "$TMP_DIR/easyrsa.tgz" -C "$TMP_DIR"
    cp -rf "$TMP_DIR"/EasyRSA-3.1.7/* /etc/openvpn/easy-rsa/
    rm -rf "$TMP_DIR"
    chmod +x /etc/openvpn/easy-rsa/easyrsa

    cd /etc/openvpn/easy-rsa/
    ./easyrsa init-pki
    SERVER_CN="openvpn-server-$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1 || echo 'prisma')"
    ./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass
    ./easyrsa --batch build-server-full server nopass
    ./easyrsa --batch gen-dh
    ./easyrsa gen-crl

    mkdir -p /etc/openvpn /etc/openvpn/server /etc/openvpn/ccd /var/log/openvpn

    # Chave TLS-Crypt (Alta segurança e camuflagem de pacotes)
    if [[ ! -s /etc/openvpn/tls-crypt.key ]]; then
        openvpn --genkey secret /etc/openvpn/tls-crypt.key 2>/dev/null || openvpn --genkey --secret /etc/openvpn/tls-crypt.key 2>/dev/null || true
    fi

    # Copiar certificados para as duas pastas (/etc/openvpn e /etc/openvpn/server)
    for DIR in /etc/openvpn /etc/openvpn/server; do
        cp -f pki/ca.crt "$DIR/ca.crt"
        cp -f pki/dh.pem "$DIR/dh2048.pem"
        cp -f pki/dh.pem "$DIR/dh.pem"
        cp -f pki/issued/server.crt "$DIR/server.crt"
        cp -f pki/private/server.key "$DIR/server.key"
        cp -f pki/crl.pem "$DIR/crl.pem"
        [ -f /etc/openvpn/tls-crypt.key ] && cp -f /etc/openvpn/tls-crypt.key "$DIR/tls-crypt.key"
    done

    chmod 644 /etc/openvpn/*.crt /etc/openvpn/*.pem /etc/openvpn/tls-crypt.key /etc/openvpn/server/*.crt /etc/openvpn/server/*.pem /etc/openvpn/server/tls-crypt.key 2>/dev/null || true
    chmod 600 /etc/openvpn/*.key /etc/openvpn/server/*.key 2>/dev/null || true

    # Montar o server.conf
    log_info "Gerando arquivo de configuração do servidor..."
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
ifconfig-pool-persist /etc/openvpn/ipp.txt
ca /etc/openvpn/ca.crt
cert /etc/openvpn/server.crt
key /etc/openvpn/server.key
dh /etc/openvpn/dh2048.pem
crl-verify /etc/openvpn/crl.pem
tls-crypt /etc/openvpn/tls-crypt.key
cipher AES-256-GCM
auth SHA256
status /var/log/openvpn/openvpn-status.log
verb 3
EOF

    # Configuração de Roteamento de acordo com a escolha do usuário
    if [[ "$ROUTING_CHOICE" == "2" ]]; then
        # Full-Tunneling
        echo 'push "redirect-gateway def1 bypass-dhcp"' >>/etc/openvpn/server.conf
        echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server.conf
        echo 'push "dhcp-option DNS 8.8.8.8"' >>/etc/openvpn/server.conf
    else
        # Split-Tunneling (Apenas rede do PBX passa pela VPN)
        echo "push \"route $VPN_SUBNET $VPN_NETMASK\"" >>/etc/openvpn/server.conf
        echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server.conf
    fi

    # Espelha o server.conf em /etc/openvpn/server/server.conf (compatibilidade Rocky 8)
    cp -f /etc/openvpn/server.conf /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/ca.crt|ca.crt|g' /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/server.crt|server.crt|g' /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/server.key|server.key|g' /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/dh2048.pem|dh2048.pem|g' /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/crl.pem|crl.pem|g' /etc/openvpn/server/server.conf
    sed -i 's|/etc/openvpn/tls-crypt.key|tls-crypt.key|g' /etc/openvpn/server/server.conf

    # ==========================================================================
    # REDE, FIREWALL & NAT (ZERO QUEDA DE INTERNET)
    # ==========================================================================
    log_info "Configurando regras de roteamento (IP Forwarding e NAT Masquerade)..."

    # 1. Ativação permanente de IP Forwarding
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-openvpn.conf
    sysctl -p /etc/sysctl.d/99-openvpn.conf 2>/dev/null || sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true

    # 2. Se o firewalld estiver ativo (comum no CentOS/Rocky), adiciona as regras nele
    if systemctl is-active firewalld &>/dev/null; then
        log_info "Firewalld ativo detectado. Adicionando regras de masquerade e portas..."
        firewall-cmd --zone=trusted --add-interface=tun0 --permanent 2>/dev/null || true
        firewall-cmd --add-masquerade --permanent 2>/dev/null || true
        firewall-cmd --add-port=${PORT}/${PROTOCOL} --permanent 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi

    # 3. Regras seguras no IPTABLES (Garante a criação da pasta /etc/iptables)
    mkdir -p /etc/iptables
    cat <<EOF >/etc/iptables/add-openvpn-rules.sh
#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s ${VPN_SUBNET}/24 -o $NIC -j MASQUERADE 2>/dev/null || true
iptables -I INPUT 1 -i tun0 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT 2>/dev/null || true
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT 2>/dev/null || true
EOF

    cat <<EOF >/etc/iptables/rm-openvpn-rules.sh
#!/bin/sh
iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}/24 -o $NIC -j MASQUERADE 2>/dev/null || true
iptables -D INPUT -i tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT 2>/dev/null || true
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT 2>/dev/null || true
EOF

    chmod +x /etc/iptables/add-openvpn-rules.sh /etc/iptables/rm-openvpn-rules.sh
    sh /etc/iptables/add-openvpn-rules.sh 2>/dev/null || true

    # Serviço systemd para persistir regras de iptables no boot
    cat <<EOF >/etc/systemd/system/iptables-openvpn.service
[Unit]
Description=iptables rules for OpenVPN Prisma
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
    systemctl enable iptables-openvpn 2>/dev/null || true
    systemctl start iptables-openvpn 2>/dev/null || true

    # ==========================================================================
    # SYSTEMD & INICIALIZAÇÃO DO SERVIÇO
    # ==========================================================================
    mkdir -p /run/openvpn /run/openvpn-server
    chown -R nobody:$NOGROUP /var/log/openvpn 2>/dev/null || true

    log_info "Iniciando e habilitando serviço OpenVPN..."
    systemctl daemon-reload

    # Cria compatibilidade entre openvpn@server e openvpn-server@server
    if [ -f /usr/lib/systemd/system/openvpn-server@.service ] && [ ! -f /etc/systemd/system/openvpn@.service ]; then
        ln -sfn /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn@.service 2>/dev/null || true
    elif [ -f /usr/lib/systemd/system/openvpn@.service ] && [ ! -f /etc/systemd/system/openvpn-server@.service ]; then
        ln -sfn /usr/lib/systemd/system/openvpn@.service /etc/systemd/system/openvpn-server@.service 2>/dev/null || true
    fi
    systemctl daemon-reload

    systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || systemctl restart openvpn 2>/dev/null || true
    systemctl enable openvpn-server@server 2>/dev/null || systemctl enable openvpn@server 2>/dev/null || true

    # Template do Cliente (.ovpn)
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
auth SHA256
cipher AES-256-GCM
verb 3
EOF

    # Salva variáveis de instalação para gerenciamento futuro
    cat <<EOF >/etc/openvpn/prisma-installer.conf
ENDPOINT="$ENDPOINT"
PORT="$PORT"
PROTOCOL="$PROTOCOL"
VPN_SUBNET="$VPN_SUBNET"
VPN_NETMASK="$VPN_NETMASK"
SERVER_GATEWAY_IP="$SERVER_GATEWAY_IP"
ROUTING_CHOICE="$ROUTING_CHOICE"
NIC="$NIC"
EOF

    # Gera o primeiro cliente
    generate_client "$CLIENT_NAME"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${WHITE}          OPENVPN PRISMA V2 INSTALADO COM SUCESSO!                    ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  IP do Servidor no Túnel: ${WHITE}$SERVER_GATEWAY_IP${NC}"
    echo -e "${GREEN}║${NC}  Porta: ${WHITE}$PORT $PROTOCOL${NC}"
    if [[ "$ROUTING_CHOICE" == "1" ]]; then
        echo -e "${GREEN}║${NC}  Modo: ${YELLOW}Split-Tunneling (Internet local mantida no cliente)${NC}"
    else
        echo -e "${GREEN}║${NC}  Modo: ${CYAN}Full-Tunneling (Navegação completa via PBX)${NC}"
    fi
    echo -e "${GREEN}║${NC}  Arquivo do Cliente gerado em: ${WHITE}$SAVED_CLIENT_PATH${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# GERAÇÃO DE CLIENTE (.ovpn)
# ==============================================================================
generate_client() {
    local client_name="$1"
    cd /etc/openvpn/easy-rsa/ || return 1

    log_info "Gerando certificado para o cliente '$client_name'..."
    ./easyrsa --batch build-client-full "$client_name" nopass >/dev/null 2>&1

    local home_dir="/root"
    if [[ -n "${SUDO_USER}" && "${SUDO_USER}" != "root" ]]; then
        home_dir="/home/${SUDO_USER}"
    fi

    SAVED_CLIENT_PATH="$home_dir/${client_name}.ovpn"

    cp -f /etc/openvpn/client-template.txt "$SAVED_CLIENT_PATH"
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
    } >>"$SAVED_CLIENT_PATH"

    chmod 600 "$SAVED_CLIENT_PATH"
    log_success "Arquivo pronto para uso: $SAVED_CLIENT_PATH"
}

# ==============================================================================
# MENU DE GERENCIAMENTO (QUANDO JÁ ESTIVER INSTALADO)
# ==============================================================================
manage_menu() {
    [ -f /etc/openvpn/prisma-installer.conf ] && source /etc/openvpn/prisma-installer.conf

    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${WHITE}             GERENCIADOR OPENVPN PRISMA V2 (INSTALADO)                ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}   [1] Adicionar novo cliente (.ovpn)                                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}   [2] Revogar acesso de um cliente                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}   [3] Ver conexões ativas / Status do Serviço                        ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}   [4] Desinstalar OpenVPN do servidor                                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}   [0] Sair                                                           ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -ne "${WHITE}Escolha uma opção [1-4, 0 para sair]: ${NC}"
        tty_read -r OPTION

        case "$OPTION" in
            1)
                echo ""
                echo -ne "${WHITE}Nome do novo cliente (ex: ramal102 ou notebook-suporte): ${NC}"
                tty_read -r NEW_CLIENT
                NEW_CLIENT=$(echo "$NEW_CLIENT" | tr -cd 'a-zA-Z0-9_-')
                if [[ -z "$NEW_CLIENT" ]]; then
                    log_error "Nome inválido."
                elif [[ -f "/etc/openvpn/easy-rsa/pki/issued/${NEW_CLIENT}.crt" ]]; then
                    log_error "Já existe um cliente com o nome '$NEW_CLIENT'."
                else
                    generate_client "$NEW_CLIENT"
                fi
                echo ""
                echo -n "Pressione ENTER para voltar ao menu..."
                tty_read -r
                ;;
            2)
                echo ""
                echo -e "${YELLOW}Clientes cadastrados atualmente:${NC}"
                tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt 2>/dev/null | grep "^V" | cut -d '=' -f 2 | grep -v "^server$" || true
                echo ""
                echo -ne "${WHITE}Digite o nome exato do cliente para revogar: ${NC}"
                tty_read -r REVOKE_CLIENT
                REVOKE_CLIENT=$(echo "$REVOKE_CLIENT" | tr -d '[:space:]')
                if [[ -n "$REVOKE_CLIENT" && -f "/etc/openvpn/easy-rsa/pki/issued/${REVOKE_CLIENT}.crt" ]]; then
                    cd /etc/openvpn/easy-rsa/
                    ./easyrsa --batch revoke "$REVOKE_CLIENT"
                    ./easyrsa gen-crl
                    cp -f pki/crl.pem /etc/openvpn/crl.pem
                    cp -f pki/crl.pem /etc/openvpn/server/crl.pem 2>/dev/null || true
                    systemctl restart openvpn-server@server 2>/dev/null || systemctl restart openvpn@server 2>/dev/null || true
                    log_success "Cliente '$REVOKE_CLIENT' revogado e túnel desconectado com sucesso."
                else
                    log_error "Cliente não encontrado."
                fi
                echo ""
                echo -n "Pressione ENTER para voltar ao menu..."
                tty_read -r
                ;;
            3)
                echo ""
                log_info "Status do Serviço:"
                systemctl status openvpn-server@server --no-pager 2>/dev/null || systemctl status openvpn@server --no-pager 2>/dev/null || true
                echo ""
                log_info "Conexões ativas (Status Log):"
                if [ -f /var/log/openvpn/openvpn-status.log ]; then
                    cat /var/log/openvpn/openvpn-status.log
                else
                    echo "Nenhum log de status gerado ainda."
                fi
                echo ""
                echo -n "Pressione ENTER para voltar ao menu..."
                tty_read -r
                ;;
            4)
                echo ""
                echo -e "${RED}TEM CERTEZA QUE DESEJA DESINSTALAR COMPLETAMENTE O OPENVPN?${NC}"
                echo -ne "Digite 'sim' para confirmar: "
                tty_read -r CONFIRM
                if [[ "$CONFIRM" == "sim" ]]; then
                    log_warn "Desinstalando OpenVPN e limpando regras..."
                    systemctl stop openvpn-server@server openvpn@server openvpn iptables-openvpn 2>/dev/null || true
                    systemctl disable openvpn-server@server openvpn@server openvpn iptables-openvpn 2>/dev/null || true
                    sh /etc/iptables/rm-openvpn-rules.sh 2>/dev/null || true
                    rm -rf /etc/openvpn /etc/iptables/add-openvpn-rules.sh /etc/iptables/rm-openvpn-rules.sh /etc/systemd/system/iptables-openvpn.service /var/log/openvpn
                    systemctl daemon-reload
                    log_success "OpenVPN removido do servidor com sucesso."
                    exit 0
                else
                    log_info "Operação cancelada."
                fi
                echo -n "Pressione ENTER para voltar ao menu..."
                tty_read -r
                ;;
            0)
                exit 0
                ;;
            *)
                log_error "Opção inválida."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# ENTRADA PRINCIPAL
# ==============================================================================
if [[ -e /etc/openvpn/server.conf ]] || [[ -e /etc/openvpn/server/server.conf ]]; then
    manage_menu
else
    install_openvpn
fi
