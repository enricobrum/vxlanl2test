#!/bin/bash

# Verifica numero di argomenti
if [ "$#" -ne 1 ]; then
    echo "Uso: $0 <VXLAN_ID>"
    echo "Esempio: $0 42"
    exit 1
fi

VXLAN_ID=$1
VXLAN_IF="vxlan${VXLAN_ID}"

echo "Rimozione dell'interfaccia $VXLAN_IF..."
sudo ip link delete $VXLAN_IF 2>/dev/null

if [ $? -eq 0 ]; then
    echo "Interfaccia $VXLAN_IF rimossa con successo."
else
    echo "Errore: impossibile rimuovere $VXLAN_IF (forse non esiste)."
fi
