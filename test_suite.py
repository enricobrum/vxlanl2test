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
        print(f"\n→ Running: {command}")
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        output = result.stdout.strip()
        print(output)
        return output if output else "No output"
    except Exception as e:
        return str(e)

def l2_test():
    role = input("Client or Server? [c/s]: ").lower()
    interface = input("Enter interface for L2 test (e.g., vxlan0): ")
    if role == 's':
        command = f"sudo python3 l2_server.py --iface {interface}"
        output = run_command(command)
        log_result("L2", "Server", interface, command, output[:200])
    else:
        ip = input("Server IP: ")
        command = f"sudo python3 l2_client.py --iface {interface} --ip {ip}"
        output = run_command(command)
        log_result("L2", "Client", interface, command, output[:200])

def iperf3_test():
    role = input("Client or Server? [c/s]: ").lower()
    if role == 's':
        command = "iperf3 -s"
        output = run_command(command)
        log_result("iPerf3", "Server", "-", command, output[:200])
    else:
        ip = input("Server IP: ")
        duration = input("Duration (sec): ")
        dscp = input("DSCP value (0–63): ")
        command = f"iperf3 -c {ip} -t {duration} --tos {int(dscp) << 2}"
        output = run_command(command)
        log_result("iPerf3", "Client", "-", command, output[:200])

def nping_test():
    role = input("Client or Server? [c/s]: ").lower()
    if role == 's':
        command = "sudo nping --echo-server"
        output = run_command(command)
        log_result("Nping", "Server", "-", command, output[:200])
    else:
        ip = input("Server IP: ")
        dscp = input("DSCP value (0–63): ")
        count = input("Ping count: ")
        command = f"sudo nping --echo-client --count {count} --data-length 10 --tos {int(dscp) << 2} {ip}"
        output = run_command(command)
        log_result("Nping", "Client", "-", command, output[:200])

def menu():
    print("\n🧪 5G + VXLAN Test Suite")
    print("1) Layer 2 (VXLAN) Echo Test")
    print("2) iperf3 Throughput Test")
    print("3) nping DSCP Echo Test")
    print("4) Exit\n")
    choice = input("Choose an option: ")
    return choice

if __name__ == "__main__":
    print("⚙️ Starting Interactive Test Suite")
    with open(csv_file, mode='w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["Timestamp", "TestType", "Role", "Interface", "Command", "ResultSummary"])

    while True:
        match menu():
            case "1": l2_test()
            case "2": iperf3_test()
            case "3": nping_test()
            case "4": print("Exiting."); break
            case _: print("Invalid choice.")
