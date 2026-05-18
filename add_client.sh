#!/bin/bash
set -e

WG_IF="wg0"
WG_PORT="51820"

# ── Укажи имя клиента и его IP в туннеле ────────────────
CLIENT_NAME="${1:-gaming_pc}"
CLIENT_TUNNEL_IP="${2:-10.0.0.2}"
# ────────────────────────────────────────────────────────

# Узнаём внешний IP сервера
SERVER_PUBLIC_IP=$(curl -s ifconfig.me)
SERVER_PUB=$(cat /etc/wireguard/server_public.key)

echo "[1/3] Генерация ключей клиента: ${CLIENT_NAME}..."
cd /etc/wireguard
umask 077
wg genkey | tee "${CLIENT_NAME}_private.key" | wg pubkey > "${CLIENT_NAME}_public.key"

CLIENT_PRIV=$(cat "${CLIENT_NAME}_private.key")
CLIENT_PUB=$(cat "${CLIENT_NAME}_public.key")

echo "[2/3] Добавление пира в серверный конфиг..."
cat >> /etc/wireguard/${WG_IF}.conf << EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_TUNNEL_IP}/32
EOF

# Применяем без перезапуска туннеля
wg set ${WG_IF} peer "${CLIENT_PUB}" allowed-ips "${CLIENT_TUNNEL_IP}/32"

echo "[3/3] Генерация клиентского конфига..."
cat > "/etc/wireguard/${CLIENT_NAME}.conf" << EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${CLIENT_TUNNEL_IP}/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_PUBLIC_IP}:${WG_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo ""
echo "══════════════════════════════════════════════"
echo " ✅ Клиент '${CLIENT_NAME}' добавлен!"
echo ""
echo " Конфиг для Windows: /etc/wireguard/${CLIENT_NAME}.conf"
echo " Скачай его на ПК:"
echo "   scp root@${SERVER_PUBLIC_IP}:/etc/wireguard/${CLIENT_NAME}.conf ."
echo ""
echo " Затем в WireGuard для Windows:"
echo "   Import tunnel → выбери скачанный .conf"
echo "══════════════════════════════════════════════"