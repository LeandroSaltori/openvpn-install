# OpenVPN Installer - Prisma PABX & Proxmox VE

Instalador e gerenciador automatizado de servidor OpenVPN com **Split-Tunneling** otimizado para servidores **Issabel PABX** (CentOS 7 / Rocky Linux 8) e **Proxmox VE** (Debian).

## 🚀 Características

- **Split-Tunneling Nativo**: Mantém a navegação de internet e o DNS local do cliente funcionando perfeitamente enquanto concede acesso à subrede do PABX/Proxmox (`177.35.0.0/24` por padrão).
- **Sem Perda de Conexão com a Internet**: Corrigido o problema de bloqueio de DNS (`block-outside-dns`) no Windows.
- **Suporte Multi-SO**:
  - CentOS 7 / Rocky Linux 8 / AlmaLinux 8 / RHEL 7-8 (Issabel PABX)
  - Proxmox VE / Debian 10, 11 e 12
- **Criptografia Otimizada e Segura**:
  - Certificados com **Elliptic Curve** (`prime256v1`) via Easy-RSA 3
  - Cifragem **AES-256-GCM** / **AES-128-GCM**
  - Autenticação HMAC **SHA256**
  - Proteção de canal de controle via **tls-crypt**
- **Sem Bloatware**: Removidos instaladores extras de DNS (Unbound), menus legados e opções desnecessárias.

---

## 🛠️ Como Usar

No servidor (CentOS 7, Rocky Linux 8 ou Proxmox VE), execute como **root**:

```bash
curl -O https://raw.githubusercontent.com/LeandroSaltori/openvpn-install/master/openvpn-install-prisma.sh
chmod +x openvpn-install-prisma.sh
./openvpn-install-prisma.sh
```

### 1. Instalação Inicial
Ao rodar pela primeira vez, o assistente solicitará:
1. **IP Público / Domínio**: Detectado automaticamente.
2. **Porta**: Padrão `1194` (UDP recomendado).
3. **Subrede VPN**: Padrão `177.35.0.0` com máscara `255.255.255.0`.
4. **Nome do Primeiro Cliente**: Ex: `suporte-prisma`.

Ao final, o arquivo `.ovpn` compilado com todos os certificados embutidos será gerado em `/root/<cliente>.ovpn`.

### 2. Gerenciamento de Clientes
Ao executar o script novamente após a instalação:

```bash
./openvpn-install-prisma.sh
```

Menu disponível:
1. **Adicionar novo cliente**: Gera um novo arquivo `.ovpn`.
2. **Revogar acesso de um cliente**: Cancela o certificado de acesso.
3. **Desinstalar OpenVPN**: Remove todas as configurações e regras de firewall.

---

## ⚙️ Gerenciamento do Serviço no Servidor

### CentOS / Rocky Linux / RHEL (Issabel PABX):
```bash
systemctl status openvpn-server@server
systemctl restart openvpn-server@server
```

### Proxmox VE / Debian:
```bash
systemctl status openvpn-server@server
# ou
systemctl status openvpn@server
```

### Regras de Firewall (IPTables Persistence):
As regras de NAT e encaminhamento são salvas em `/etc/iptables/add-openvpn-rules.sh` e gerenciadas pelo serviço systemd `iptables-openvpn`.

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais detalhes.
