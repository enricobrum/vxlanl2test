#!/bin/bash

# Script per configurare la connessione USB su Raspberry Pi

sudo dhclient -v usb0

# Configurazione IP statico per l'interfaccia USB
sudo udhcpc -i usb0

# Aggiunta della route predefinita per l'interfaccia USB
sudo route add -net 0.0.0.0 usb0