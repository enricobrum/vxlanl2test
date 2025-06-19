#!/bin/bash

# Verifica numero di argomenti
if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <VXLAN_ID> $1 <BR_ID>
    echo "Esempio: $0 42 $1 br42"

    exit 1
fi

VXLAN_ID=$1
BR_ID=$2
BRIDGE_IF="br${BR_ID}"
VXLAN_IF="vxlan${VXLAN_ID}"

echo "Rimozione dell'interfaccia $VXLAN_IF..."

sudo ip link delete $VXLAN_IF 2>/dev/null
sudo ip link delete 
if [ $? -eq 0 ]; then
    echo "Interfaccia $VXLAN_IF rimossa con successo."
else
    echo "Errore: impossibile rimuovere $VXLAN_IF (forse non esiste)."
fi

echo "Rimozione del bridge $BRIDGE_IF..."
sudo ip link delete $BRIDGE_IF 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Bridge $BRIDGE_IF rimosso con successo."
else
    echo "Errore: impossibile rimuovere $BRIDGE_IF (forse non esiste)."
fi

