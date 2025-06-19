#!/usr/bin/env python3
"""
Enhanced Layer 2 Test Client
Supports:
- RTT measurement
- Throughput test
- Load test (stress)
- Variable frame size test
- Data integrity verification
- VLAN tagging
- Jitter analysis
All results are saved in CSV format per test.
"""
import socket
import struct
import time
import os
import csv
import fcntl
import binascii
import random
from datetime import datetime

# Constants
ETH_P_ALL = 0x0003
ETH_P_8021Q = 0x8100
DEFAULT_ETHERTYPE = 0x88B5

# Utility functions
def get_src_mac(ifname):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    info = fcntl.ioctl(s.fileno(), 0x8927, struct.pack('256s', ifname[:15].encode('utf-8')))
    return info[18:24]

def mac_str_to_bytes(mac_str):
    return bytes(int(b, 16) for b in mac_str.split(':'))

def bytes_to_mac_str(b):
    return ':'.join(f'{x:02x}' for x in b)

def generate_payload(size):
    return os.urandom(size)

def add_vlan_tag(dst_mac, src_mac, vlan_id, ethertype, payload):
    vlan_header = struct.pack('!HH', ETH_P_8021Q, vlan_id)
    return dst_mac + src_mac + vlan_header + struct.pack('!H', ethertype) + payload

def build_frame(dst_mac, src_mac, ethertype, payload, vlan_id=None):
    if vlan_id is not None:
        return add_vlan_tag(dst_mac, src_mac, vlan_id, ethertype, payload)
    return dst_mac + src_mac + struct.pack('!H', ethertype) + payload

def save_csv(filename, header, rows):
    with open(filename, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(header)
        writer.writerows(rows)

# Test functions
def rtt_test(send_sock, recv_sock, dst_mac, src_mac, ethertype, payload, count, interval):
    results = []
    frame = build_frame(dst_mac, src_mac, ethertype, payload)
    recv_sock.settimeout(1.0)
    print("Starting RTT test...")
    for i in range(count):
        t_send = time.time()
        send_sock.send(frame)
        try:
            while True:
                recv_frame, _ = recv_sock.recvfrom(65535)
                if len(recv_frame) < 14:
                    continue
                r_dst, r_src, r_ethertype = recv_frame[:6], recv_frame[6:12], struct.unpack('!H', recv_frame[12:14])[0]
                if r_src == dst_mac and r_dst == src_mac and r_ethertype == ethertype:
                    if recv_frame[14:] == payload:
                        t_recv = time.time()
                        rtt = (t_recv - t_send) * 1000
                        print(f"[{i+1}] RTT: {rtt:.3f} ms")
                        results.append([i+1, rtt])
                        break
        except socket.timeout:
            print(f"[{i+1}] Timeout")
            results.append([i+1, 'timeout'])
        time.sleep(interval)
    save_csv('rtt_test.csv', ['Seq', 'RTT_ms'], results)

def throughput_test(send_sock, recv_sock, dst_mac, src_mac, ethertype, payload, duration):
    frame = build_frame(dst_mac, src_mac, ethertype, payload)
    recv_sock.settimeout(1.0)
    sent = 0
    received = 0
    print("Starting throughput test...")
    start_time = time.time()
    while time.time() - start_time < duration:
        send_sock.send(frame)
        sent += 1
        try:
            recv_frame, _ = recv_sock.recvfrom(65535)
            if recv_frame[6:12] == dst_mac:
                received += 1
        except socket.timeout:
            pass
    elapsed = time.time() - start_time
    throughput = (received * len(payload) * 8) / elapsed
    print(f"Sent: {sent}, Received: {received}, Throughput: {throughput:.2f} bps")
    save_csv('throughput_test.csv', ['Sent', 'Received', 'Throughput_bps'], [[sent, received, throughput]])

def jitter_test(send_sock, recv_sock, dst_mac, src_mac, ethertype, payload, count, interval):
    frame = build_frame(dst_mac, src_mac, ethertype, payload)
    recv_sock.settimeout(1.0)
    timestamps = []
    print("Starting jitter test...")
    for i in range(count):
        t_send = time.time()
        send_sock.send(frame)
        try:
            while True:
                recv_frame, _ = recv_sock.recvfrom(65535)
                if recv_frame[6:12] == dst_mac:
                    t_recv = time.time()
                    timestamps.append(t_recv - t_send)
                    break
        except socket.timeout:
            pass
        time.sleep(interval)
    jitter_values = [abs(timestamps[i] - timestamps[i-1]) * 1000 for i in range(1, len(timestamps))]
    save_csv('jitter_test.csv', ['Sample', 'Jitter_ms'], list(enumerate(jitter_values, start=1)))
    print("Jitter test complete.")

def integrity_test(send_sock, recv_sock, dst_mac, src_mac, ethertype, payload, count):
    frame = build_frame(dst_mac, src_mac, ethertype, payload)
    recv_sock.settimeout(1.0)
    errors = 0
    print("Starting integrity test...")
    for i in range(count):
        send_sock.send(frame)
        try:
            recv_frame, _ = recv_sock.recvfrom(65535)
            if recv_frame[14:] != payload:
                errors += 1
        except socket.timeout:
            errors += 1
    print(f"Total errors: {errors} out of {count}")
    save_csv('integrity_test.csv', ['Sent', 'Errors'], [[count, errors]])

def variable_frame_test(send_sock, recv_sock, dst_mac, src_mac, ethertype, sizes):
    results = []
    recv_sock.settimeout(1.0)
    print("Starting variable frame size test...")
    for size in sizes:
        payload = generate_payload(size)
        frame = build_frame(dst_mac, src_mac, ethertype, payload)
        send_sock.send(frame)
        try:
            recv_frame, _ = recv_sock.recvfrom(65535)
            received = len(recv_frame)
        except socket.timeout:
            received = 0
        results.append([size, received])
    save_csv('frame_size_test.csv', ['Payload_Bytes', 'Received_Bytes'], results)

def main():
    interface = input("Enter interface name: ").strip()
    dst_mac_str = input("Enter destination MAC address (e.g., aa:bb:cc:dd:ee:ff): ").strip()
    vlan_input = input("Use VLAN? (y/n): ").lower().strip()
    vlan_id = int(input("Enter VLAN ID (0-4095): ")) if vlan_input == 'y' else None

    dst_mac = mac_str_to_bytes(dst_mac_str)
    src_mac = get_src_mac(interface)

    send_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    send_sock.bind((interface, 0))
    recv_sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(DEFAULT_ETHERTYPE))
    recv_sock.bind((interface, 0))

    while True:
        print("\nAvailable Tests:")
        print("1. RTT Test")
        print("2. Throughput Test")
        print("3. Jitter Test")
        print("4. Integrity Test")
        print("5. Variable Frame Size Test")
        print("6. Exit")
        choice = input("Select test: ").strip()

        if choice == '1':
            count = int(input("Enter packet count: "))
            interval = float(input("Enter interval between packets (s): "))
            payload = generate_payload(100)
            rtt_test(send_sock, recv_sock, dst_mac, src_mac, DEFAULT_ETHERTYPE, payload, count, interval)

        elif choice == '2':
            duration = float(input("Enter test duration (s): "))
            payload = generate_payload(500)
            throughput_test(send_sock, recv_sock, dst_mac, src_mac, DEFAULT_ETHERTYPE, payload, duration)

        elif choice == '3':
            count = int(input("Enter packet count: "))
            interval = float(input("Enter interval between packets (s): "))
            payload = generate_payload(100)
            jitter_test(send_sock, recv_sock, dst_mac, src_mac, DEFAULT_ETHERTYPE, payload, count, interval)

        elif choice == '4':
            count = int(input("Enter packet count: "))
            payload = generate_payload(100)
            integrity_test(send_sock, recv_sock, dst_mac, src_mac, DEFAULT_ETHERTYPE, payload, count)

        elif choice == '5':
            sizes = [64, 128, 256, 512, 1024, 1500]
            variable_frame_test(send_sock, recv_sock, dst_mac, src_mac, DEFAULT_ETHERTYPE, sizes)

        elif choice == '6':
            break

        else:
            print("Invalid selection.")

    send_sock.close()
    recv_sock.close()

if __name__ == '__main__':
    main()
