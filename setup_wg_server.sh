#!/bin/bash
set -e

# ── Конфиг ──────────────────────────────────────────────
WG_IF="wg0"
WG_PORT="51820"
WG_SUBNET="10.0.0.0/24"
SERVER_IP="10.0.0.1/24"
# ────────────────────────────────────────────────────────

echo "[1/6] Обновление пакетов и установка WireGuard..."
apt-get update -q
apt-get install -y wireguard iptables

echo "[2/6] Генерация ключей сервера..."
mkdir -p /etc/wireguard
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

SERVER_PRIV=$(cat server_private.key)
SERVER_PUB=$(cat server_public.key)

echo "[3/6] Определение внешнего интерфейса..."
EXT_IF=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
echo "    Внешний интерфейс: $EXT_IF"

echo "[4/6] Создание конфига /etc/wireguard/${WG_IF}.conf..."
cat > /etc/wireguard/${WG_IF}.conf << EOF
[Interface]
Address = ${SERVER_IP}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

# Форвардинг трафика клиентов
PostUp   = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; \
           iptables -A FORWARD -o ${WG_IF} -j ACCEPT; \
           iptables -t nat -A POSTROUTING -o ${EXT_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; \
           iptables -D FORWARD -o ${WG_IF} -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o ${EXT_IF} -j MASQUERADE

# --- Клиенты добавляются ниже командой add_client ---
EOF

echo "[5/6] Включение IP-форвардинга..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf \
    || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

echo "[6/6] Запуск WireGuard..."
systemctl enable wg-quick@${WG_IF}
systemctl start  wg-quick@${WG_IF}

echo ""
echo "══════════════════════════════════════════════"
echo " ✅ Сервер готов!"
echo "    Публичный ключ сервера:"
echo "    ${SERVER_PUB}"
echo ""
echo " Следующий шаг: запустите add_client.sh"
echo "══════════════════════════════════════════════"