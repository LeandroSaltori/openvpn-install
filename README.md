# OpenVPN Server Installer - Prisma PABX & Proxmox VE

Script automatizado para instalação e gerenciamento de Servidores OpenVPN otimizado para ambientes **Prisma PABX (Issabel em CentOS 7 / Rocky Linux 8)** e **Proxmox VE**.

---

## 🚀 Características

- **Compatibilidade Garantida**: Testado e homologado para CentOS 7, Rocky Linux 8 e Proxmox VE / Debian.
- **Suporte a Split Tunneling**: Configurado por padrão para não redirecionar todo o tráfego de internet do cliente, mantendo a navegação local intacta.
- **Gerenciamento de Regras de Firewall**: Criação e persistência automática de regras iptables para o ambiente PABX.
- **Segurança de Nível Comercial**:
  - Cifragem **AES-256-GCM** / **AES-128-GCM**
  - Autenticação HMAC **SHA256**
  - Proteção de canal de controle via **tls-crypt**

---

## 🛠️ Como Usar

No servidor (CentOS 7, Rocky Linux 8 ou Proxmox VE), execute como **root**:

```bash
curl -O https://raw.githubusercontent.com/LeandroSaltori/openvpn-install/master/FUNCIONADNDO-openvpn-install-prisma.sh
chmod +x FUNCIONADNDO-openvpn-install-prisma.sh
./FUNCIONADNDO-openvpn-install-prisma.sh
```

### 1. Instalação Inicial
Ao rodar pela primeira vez, o assistente solicitará:
1. **IP Público / Domínio**: Informe o IP Público ou o endereço DDNS (ex: `alphasis.ddns.com.br`).
2. **Porta**: Padrão `1194` (UDP recomendado).
3. **Subrede VPN**: Padrão `177.35.0.0` com máscara `255.255.255.0`.
4. **Nome do Primeiro Cliente**: Ex: `suporte-prisma`.

Ao final, o arquivo `.ovpn` compilado com todos os certificados embutidos será gerado em `/root/<cliente>.ovpn`.

### 2. Gerenciamento de Clientes
Ao executar o script novamente após a instalação:

```bash
./FUNCIONADNDO-openvpn-install-prisma.sh
```

Menu disponível:
1. **Adicionar um novo cliente**
2. **Revogar um cliente existente**
3. **Remover o OpenVPN do servidor**

---

## ⚙️ Gerenciamento do Serviço

### Status e Reinício do Serviço:
```bash
systemctl status openvpn@server
systemctl restart openvpn@server
```

---

## 📄 Licença

Distribuído sob a licença MIT. Veja `LICENSE` para mais detalhes.
