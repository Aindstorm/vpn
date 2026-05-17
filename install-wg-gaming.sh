#!/usr/bin/env bash
set -e

WG_IF="wg0"
WG_PORT="51820"
WG_NET="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1/24"
WG_CLIENT_IP="10.66.66.2/32"
CLIENT_NAME="gaming-pc"
DNS1="1.1.1.1"
DNS2="1.0.0.1"

echo "[*] Detecting network interface..."
SERVER_IF=$(ip route get 1.1.1.1 | awk '{print $5; exit}')

echo "[*] Updating system..."
apt update
apt install -y wireguard qrencode curl iptables iproute2 ethtool

echo "[*] Enabling IP forwarding..."
cat >/etc/sysctl.d/99-wireguard.conf <<EOF
# forwarding
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1

# BBR
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# gaming tuning
net.core.netdev_max_backlog=250000
net.core.somaxconn=65535

net.core.rmem_max=67108864
net.core.wmem_max=67108864

net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

net.ipv4.tcp_fastopen=3
net.ipv4.tcp_mtu_probing=1

net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=600

# reduce latency spikes
net.ipv4.tcp_slow_start_after_idle=0

# better buffers
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432

# fq_codel
net.core.default_qdisc=fq_codel
EOF

sysctl --system

echo "[*] Applying fq_codel..."
tc qdisc replace dev $SERVER_IF root fq_codel || true

echo "[*] Generating keys..."
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
wg genkey | tee /etc/wireguard/client.key | wg pubkey > /etc/wireguard/client.pub

SERVER_PRIV=$(cat /etc/wireguard/server.key)
SERVER_PUB=$(cat /etc/wireguard/server.pub)

CLIENT_PRIV=$(cat /etc/wireguard/client.key)
CLIENT_PUB=$(cat /etc/wireguard/client.pub)

SERVER_IP=$(curl -4 -s https://ipv4.icanhazip.com)

echo "[*] Creating WireGuard config..."

cat >/etc/wireguard/${WG_IF}.conf <<EOF
[Interface]
Address = ${WG_SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

# performance
MTU = 1420

PostUp = iptables -A FORWARD -i ${WG_IF} -j ACCEPT
PostUp = iptables -A FORWARD -o ${WG_IF} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${SERVER_IF} -j MASQUERADE

PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT
PostDown = iptables -D FORWARD -o ${WG_IF} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${SERVER_IF} -j MASQUERADE

[Peer]
PublicKey = ${CLIENT_PUB}
AllowedIPs = 10.66.66.2/32
EOF

chmod 600 /etc/wireguard/${WG_IF}.conf

echo "[*] Starting WireGuard..."
systemctl enable wg-quick@${WG_IF}
systemctl restart wg-quick@${WG_IF}

echo "[*] Creating client config..."

cat > ~/${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${WG_CLIENT_IP}
DNS = ${DNS1}, ${DNS2}

# gaming MTU
MTU = 1420

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${WG_PORT}

AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

echo
echo "========================================"
echo "WireGuard Gaming VPN Installed"
echo "========================================"
echo
echo "Server IP: ${SERVER_IP}"
echo "WG Interface: ${WG_IF}"
echo "WG Port: ${WG_PORT}"
echo
echo "Client config:"
echo "~/$(basename ~/${CLIENT_NAME}.conf)"
echo

qrencode -t ansiutf8 < ~/${CLIENT_NAME}.conf

echo
echo "[*] Done."