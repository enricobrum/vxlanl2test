#!/bin/bash

# Usage:
# sudo ./vxlan_bridge_setup.sh -i enp0s8 -v 42 -s 10.10.10.0/24 -x 1 [-r 192.168.56.2] [-e tap0,veth1]

set -e

# Default
VXLAN_PORT=4789
MULTICAST_GROUP="239.1.1.1"

# Arg parsing
while getopts ":i:v:s:x:r:e:" opt; do
  case $opt in
    i) PHYS_IF=$OPTARG ;;                  # Interfaccia fisica (es. enp0s8)
    v) VXLAN_ID=$OPTARG ;;                 # ID VXLAN
    s) SUBNET=$OPTARG ;;                   # Subnet (es. 10.10.10.0/24)
    x) HOST_ID=$OPTARG ;;                  # Host ID (es. 1)
    r) REMOTE_IP=$OPTARG ;;                # Remote endpoint (unicast)
    e) EXTRA_IFS=$OPTARG ;;                # Altre interfacce da aggiungere al bridge (separate da virgola)
    \?) echo "Invalid option -$OPTARG" >&2; exit 1 ;;
  esac
done

# Verifica param obbligatori
if [[ -z "$PHYS_IF" || -z "$VXLAN_ID" || -z "$SUBNET" || -z "$HOST_ID" ]]; then
  echo "Uso: $0 -i <if> -v <vxlan_id> -s <subnet> -x <host_id> [-r <remote_ip>] [-e <if1,if2>]"
  exit 1
fi

# Derivazione nomi
VXLAN_IF="vxlan${VXLAN_ID}"
BR_IF="br${VXLAN_ID}"
IP_ADDR="$(echo $SUBNET | cut -d'/' -f1 | awk -F. -v id=$HOST_ID '{printf "%d.%d.%d.%d\n", $1, $2, $3, id}')"
MAC_ADDR=$(printf "02:00:00:%02x:%02x:%02x" $VXLAN_ID 0 $HOST_ID)

echo "[*] Configurazione VXLAN bridge"
echo "    - Dev fisico : $PHYS_IF"
echo "    - VXLAN ID   : $VXLAN_ID"
echo "    - IP bridge  : $IP_ADDR"
echo "    - MAC        : $MAC_ADDR"
echo "    - Bridge     : $BR_IF"
echo "    - VXLAN IF   : $VXLAN_IF"
if [[ -n "$REMOTE_IP" ]]; then
  echo "    - Modalità   : UNICAST verso $REMOTE_IP"
else
  echo "    - Modalità   : MULTICAST ($MULTICAST_GROUP)"
fi

# Crea bridge
sudo ip link add name $BR_IF type bridge || true
sudo ip link set $BR_IF up

# Crea interfaccia VXLAN
if [[ -n "$REMOTE_IP" ]]; then
  sudo ip link add $VXLAN_IF type vxlan id $VXLAN_ID dev $PHYS_IF remote $REMOTE_IP dstport $VXLAN_PORT
else
  sudo ip link add $VXLAN_IF type vxlan id $VXLAN_ID dev $PHYS_IF group $MULTICAST_GROUP dstport $VXLAN_PORT
fi

# MAC opzionale
sudo ip link set dev $VXLAN_IF address $MAC_ADDR

# Connetti al bridge
sudo ip link set $VXLAN_IF master $BR_IF
sudo ip link set $VXLAN_IF up

# Altre interfacce
IFS=',' read -ra EXTRAS <<< "$EXTRA_IFS"
for extra_if in "${EXTRAS[@]}"; do
  if [[ -n "$extra_if" ]]; then
    echo "[+] Collegamento $extra_if al bridge"
    sudo ip link set $extra_if up
    sudo ip link set $extra_if master $BR_IF
  fi
done

# IP al bridge
sudo ip addr add $IP_ADDR/24 dev $BR_IF

# Assicura l'interfaccia fisica sia attiva
sudo ip link set $PHYS_IF up

echo "[✓] VXLAN con bridge configurato con successo"
