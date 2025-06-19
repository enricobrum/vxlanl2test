#!/usr/bin/env python3
"""
l2_echo_server.py: Listen for Ethernet frames of specified EtherType and echo them back.
Usage: sudo python3 l2_echo_server.py <interface> <ethertype>
Example: sudo python3 l2_echo_server.py eth0 0x88B5
"""

import socket
import sys
import struct
import binascii

def mac_str_to_bytes(mac_str):
    return bytes(int(b, 16) for b in mac_str.split(':'))

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

    # Create raw socket to receive all protocols
    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ethertype))
    except PermissionError:
        print("Permission denied: run as root.")
        sys.exit(1)

    sock.bind((interface, 0))
    print(f"L2 echo server listening on {interface}, EtherType 0x{ethertype:04X}")
    while True:
        # Receive raw Ethernet frame
        frame, addr = sock.recvfrom(65535)
        # Parse Ethernet header: dst(6), src(6), ethertype(2), payload...
        if len(frame) < 14:
            continue
        dst_mac = frame[0:6]
        src_mac = frame[6:12]
        recv_ethertype = struct.unpack('!H', frame[12:14])[0]
        if recv_ethertype != ethertype:
            # Not our EtherType; ignore
            continue

        payload = frame[14:]
        print(f"Received frame from {binascii.hexlify(src_mac).decode()} len={len(payload)}")
        # Construct echo frame: swap src/dst
        echo_frame = src_mac + dst_mac + struct.pack('!H', ethertype) + payload
        # Send back
        try:
            sock.send(echo_frame)
            print(f"Echoed back to {binascii.hexlify(src_mac).decode()}")
        except Exception as e:
            print(f"Error sending echo: {e}")

if __name__ == "__main__":
    main()
