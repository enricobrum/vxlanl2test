#!/usr/bin/env python3
"""
Enhanced Layer 2 Echo Server
Supports:
- Echoing frames with or without VLAN tags
- Logging of source MAC, EtherType, VLAN ID (if present), and payload size
"""

import socket
import sys
import struct
import binascii

ETH_P_ALL = 0x0003
ETH_P_8021Q = 0x8100


def mac_str_to_bytes(mac_str):
    return bytes(int(b, 16) for b in mac_str.split(':'))

def bytes_to_mac_str(b):
    return ':'.join(f'{x:02x}' for x in b)

def main():
    if len(sys.argv) != 3:
        print(f"Usage: sudo {sys.argv[0]} <interface> <ethertype (e.g., 0x88B5)>")
        sys.exit(1)

    interface = sys.argv[1]
    ethertype_str = sys.argv[2]
    try:
        ethertype = int(ethertype_str, 16)
    except ValueError:
        print("Invalid EtherType. Use hex, e.g., 0x88B5.")
        sys.exit(1)

    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ETH_P_ALL))
    except PermissionError:
        print("Permission denied: run as root.")
        sys.exit(1)

    sock.bind((interface, 0))
    print(f"Enhanced L2 Echo Server listening on {interface}, filtering EtherType 0x{ethertype:04X}")

    while True:
        frame, _ = sock.recvfrom(65535)
        if len(frame) < 14:
            continue

        dst_mac = frame[0:6]
        src_mac = frame[6:12]
        ethertype_field = struct.unpack('!H', frame[12:14])[0]

        vlan_tag = None
        actual_ethertype = ethertype_field
        payload_offset = 14

        if ethertype_field == ETH_P_8021Q and len(frame) >= 18:
            vlan_tag = frame[14:18]
            actual_ethertype = struct.unpack('!H', frame[16:18])[0]
            payload_offset = 18

        if actual_ethertype != ethertype:
            continue

        payload = frame[payload_offset:]
        src_mac_str = binascii.hexlify(src_mac).decode()

        if vlan_tag:
            vlan_id = struct.unpack('!H', vlan_tag[2:])[0] & 0x0FFF
            print(f"[VLAN {vlan_id}] Received frame from {src_mac_str}, size = {len(payload)}")
            echo_frame = src_mac + dst_mac + vlan_tag + struct.pack('!H', actual_ethertype) + payload
        else:
            print(f"Received frame from {src_mac_str}, size = {len(payload)}")
            echo_frame = src_mac + dst_mac + struct.pack('!H', actual_ethertype) + payload

        try:
            sock.send(echo_frame)
            print(f"Echoed back to {src_mac_str}")
        except Exception as e:
            print(f"Error sending echo: {e}")

if __name__ == "__main__":
    main()
