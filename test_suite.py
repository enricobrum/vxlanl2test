#!/usr/bin/env python3
import subprocess
import time
import csv
import os
from datetime import datetime

CSV_DIR = "logs"
os.makedirs(CSV_DIR, exist_ok=True)
csv_file = os.path.join(CSV_DIR, f"results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv")

def log_result(test_type, role, interface, command, result_summary):
    timestamp = datetime.now().isoformat()
    with open(csv_file, mode='a', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([timestamp, test_type, role, interface, command, result_summary])

def run_command(command):
    try:
        print(f"\nRunning: {command}")
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        output = result.stdout.strip()
        print(output)
        return output if output else "No output"
    except Exception as e:
        return str(e)

def save_output_log(prefix, output):
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_path = os.path.join(CSV_DIR, f"{prefix}_log_{timestamp}.txt")
    with open(log_path, 'w') as f:
        f.write(output)
        
def l2_test():
    role = input("Client or Server? [c/s]: ").lower()
    interface = input("Enter interface for L2 test (e.g., vxlan0): ")
    ethertype = input("Enter EtherType (e.g., 0x88B5): ")

    if role == 's':
        command = f"sudo python3 l2_server.py {interface} {ethertype}"
        output = run_command(command)
        log_result("L2", "Server", interface, command, output[:200])
        save_output_log("l2_server", output)
    else:
        dst_mac = input("Destination MAC address (e.g., aa:bb:cc:dd:ee:ff): ")
        payload = input("Payload (e.g., Hello): ")
        count = input("How many frames to send?: ")
        interval = input("Interval between frames (sec): ")

        command = f"sudo python3 l2_client.py {interface} {dst_mac} {ethertype} \"{payload}\" {count} {interval}"
        output = run_command(command)
        log_result("L2", "Client", interface, command, output[:200])
        save_output_log("l2_client", output)

def iperf3_test():
    role = input("Client or Server? [c/s]: ").lower()
    if role == 's':
        command = "iperf3 -s"
        output = run_command(command)
        log_result("iPerf3", "Server", "-", command, output[:200])
        save_output_log("iperf3_server", output)
    else:
        ip = input("Server IP: ")
        duration = input("Duration (sec): ")
        dscp = input("DSCP value (0–63): ")
        command = f"iperf3 -c {ip} -t {duration} --tos 184"
        output = run_command(command)
        log_result("iPerf3", "Client", "-", command, output[:200])
        save_output_log("iperf3_client", output)
        
def iperf3_test_crit():
        ip = input("Server IP: ")
        duration = input("Duration (sec): ")
        command = f"iperf3 -c {ip} -t {duration} --tos 192"
        output = run_command(command)
        log_result("iPerf3", "Client-Critical", "-", command, output[:200])
        save_output_log("iperf3_client_critical", output)
        
def nping_test():
    role = input("Client or Server? [c/s]: ").lower()
    if role == 's':
        command = 'sudo nping "public" --echo-server -e vxlan42'
        output = run_command(command)
        log_result("Nping", "Server", "-", command, output[:200])
        save_output_log("nping_server", output)
    else:
        ip = input("Server IP: ")
        count = input("Ping count: ")
        command = f'sudo nping "public" --echo-client --count {count} --data-length 10 --tos 184'
        output = run_command(command)
        log_result("Nping", "Client", "-", command, output[:200])
        save_output_log("nping_client", output)
        
def menu():
    print("\n 5G + VXLAN Test Suite")
    print("1) Layer 2 (VXLAN) Echo Test")
    print("2) iperf3 Throughput Test")
    print("3) nping DSCP Echo Test")
    print("4) iperf3 Critical DSCP Test")
    print("5) Exit\n")
    choice = input("Choose an option: ")
    return choice

if __name__ == "__main__":
    print("Starting Interactive Test Suite")
    with open(csv_file, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["Timestamp", "TestType", "Role", "Interface", "Command", "ResultSummary"])

    while True:
        choice=menu()
        if choice=="1": l2_test()
        elif choice=="2": iperf3_test()
        elif choice=="3": nping_test()
        elif choice=="4": iperf3_test_crit()
        elif choice=="5": print("Exiting."); break
        else: print("Invalid choice.")
