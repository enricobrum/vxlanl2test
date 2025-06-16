#!/usr/bin/env python3
"""
l2_echo_client.py: Send raw Ethernet frames to a destination MAC and wait for echo replies.
Usage: sudo python3 l2_echo_client.py <interface> <dst_mac> <ethertype> <payload> <count> <interval>
Example: sudo python3 l2_echo_client.py eth0 aa:bb:cc:dd:ee:ff 0x88B5 "Hello" 10 0.1
"""

import socket
import sys
import struct
import time
import binascii
import fcntl

def get_src_mac(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    info = fcntl.ioctl(s.fileno(), 0x8927, struct.pack('256s', ifname.encode('utf-8')))
    return info[18:24]

def mac_str_to_bytes(mac_str):
    return bytes(int(b, 16) for b in mac_str.split(':'))

def main():
    if len(sys.argv) != 7:
        print(f"Usage: sudo {sys.argv[0]} <interface> <dst_mac> <ethertype> <payload> <count> <interval>")
        sys.exit(1)

    interface = sys.argv[1]
    dst_mac_str = sys.argv[2]
    ethertype_str = sys.argv[3]
    payload_str = sys.argv[4]
    count = int(sys.argv[5])
    interval = float(sys.argv[6])

    try:
        dst_mac = mac_str_to_bytes(dst_mac_str)
    except:
        print("Invalid destination MAC format.")
        sys.exit(1)
    try:
        ethertype = int(ethertype_str, 16)
    except ValueError:
        print("Invalid EtherType. Use hex, e.g., 0x88B5.")
        sys.exit(1)
    src_mac = get_src_mac(interface)
    print(f"Interface {interface}, src MAC {binascii.hexlify(src_mac).decode()} -> dst {dst_mac_str}, EtherType 0x{ethertype:04X}")

    # Create raw socket for sending and receiving
    try:
        send_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
        send_sock.bind((interface, 0))
        # For receiving only frames of our EtherType:
        recv_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(ethertype))
        recv_sock.bind((interface, 0))
    except PermissionError:
        print("Permission denied: run as root.")
        sys.exit(1)

    # Build frame template: dst(6) + src(6) + ethertype(2) + payload
    payload_bytes = payload_str.encode()
    header = dst_mac + src_mac + struct.pack('!H', ethertype)
    frame = header + payload_bytes
    # Set timeout on recv socket
    recv_sock.settimeout(1.0)

    for i in range(count):
        t_send = time.time()
        try:
            send_sock.send(frame)
        except Exception as e:
            print(f"Error sending frame: {e}")
            break
        # Wait for echo reply: src/dst swapped: dst_mac->src_mac; so reply frame dst= our MAC, src=dst_mac
        try:
            while True:
                recv_frame, _ = recv_sock.recvfrom(65535)
                # Parse; ensure it’s echo: EtherType matches, and source MAC is dst_mac
                if len(recv_frame) < 14:
                    continue
                r_dst = recv_frame[0:6]
                r_src = recv_frame[6:12]
                r_ethertype = struct.unpack('!H', recv_frame[12:14])[0]
                if r_ethertype != ethertype:
                    continue
                if r_src == dst_mac and r_dst == src_mac:
                    t_recv = time.time()
                    r_payload = recv_frame[14:]
                    # Optionally verify payload matches
                    if r_payload != payload_bytes:
                        print("Received payload mismatch.")
                    rtt = (t_recv - t_send) * 1000.0
                    print(f"[{i+1}] RTT = {rtt:.3f} ms")
                    break
                # else ignore
        except socket.timeout:
            print(f"[{i+1}] No echo received (timeout)")
        time.sleep(interval)

    send_sock.close()
    recv_sock.close()

if __name__ == "__main__":
    main()
