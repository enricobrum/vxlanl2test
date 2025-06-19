#!/bin/bash

# Verifica numero di argomenti
if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    echo "Uso: $0 <VXLAN_ID> <INTERFACCIA_FISICA> <BASE_IP/SUBNET> [NODE_ID] [REMOTE_IP]"
    echo "Esempio: $0 42 enp0s8 10.10.10.0/24 3"
    exit 1
fi

VXLAN_ID=$1
PHYS_IF=$2
BASE_IP_CIDR=$3
NODE_ID=${4:-1}  # default NODE_ID = 1 se non specificato
REMOTE_IP=$5
# Parsing IP base e netmask
IFS='/' read -r BASE_IP SUBNET <<< "$BASE_IP_CIDR"
IFS='.' read -r IP1 IP2 IP3 IP4 <<< "$BASE_IP"

# Costruisci IP finale sostituendo l’ultimo byte con NODE_ID
FINAL_IP="${IP1}.${IP2}.${IP3}.${NODE_ID}/${SUBNET}"

# Nome interfaccia VXLAN
VXLAN_IF="vxlan${VXLAN_ID}"

# MAC address statico: primi byte fissi, ultimi 3 derivati da VNI e NODE_ID
VXLAN_MAC=$(printf '02:00:%02x:%02x:%02x:%02x' $((VXLAN_ID>>8 & 0xFF)) $((VXLAN_ID & 0xFF)) 0x00 $NODE_ID)


echo "Creazione interfaccia VXLAN $VXLAN_IF con ID $VXLAN_ID su $PHYS_IF"
sudo ip link add $VXLAN_IF type vxlan id $VXLAN_ID dev $PHYS_IF remote $REMOTE_IP dstport 4789

echo "Assegnazione MAC address $VXLAN_MAC"
sudo ip link set dev $VXLAN_IF address $VXLAN_MAC

echo "Assegnazione IP address $FINAL_IP"
sudo ip addr add $FINAL_IP dev $VXLAN_IF

echo "Attivazione interfaccia $VXLAN_IF"
sudo ip link set $VXLAN_IF up

echo "Configurazione completata!"
