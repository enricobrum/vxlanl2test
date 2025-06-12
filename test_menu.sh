#!/bin/bash
#
# test_menu.sh: Interactive menu for choosing role and test type, with extended features and environment checks.
# Features:
#  - Auto MAC discovery from IP
#  - DSCP verification via tcpdump
#  - Iperf3 server/client tests
#  - Netem impairment setup/clear
#  - Persisting defaults in a config file
#  - ARP-based MAC lookup
#  - Nping echo tests
#  - L2 raw-Ethernet echo tests
#  - Environment checks (interfaces, firewall, DSCP→QFI alignment reminder)
#  - Combined tests (bulk + prioritized)
#
# Usage: sudo ./test_menu.sh
# Requirements: nping, iperf3, tcpdump, arping, iproute2 (tc), python3

# Config file to store defaults
CFG_FILE="$HOME/.test_menu.conf"

# Load or initialize defaults
load_defaults() {
    # Default values
    ECHO_PASSPHRASE="test123"
    ECHO_PORT=4000
    DEFAULT_DSCP=46
    DEFAULT_DATA_LEN=500
    DEFAULT_RATE=10
    DEFAULT_INTERVAL="100ms"
    L2_INTERFACE="eth0"
    VXLAN_INTERFACE="vxlan0"
    WWAN_INTERFACE="wwan0"
    L2_ETHER_TYPE="0x88B5"
    L2_PAYLOAD="HelloL2"
    NPING_SERVER_IP=""
    IPERF_PORT=5201

    # Netem defaults
    NETEM_DEV=""       # interface to apply netem
    NETEM_DELAY=""     # e.g., "10ms"
    NETEM_JITTER=""    # e.g., "5ms"
    NETEM_LOSS=""      # e.g., "1%"

    # Load from config if exists
    if [[ -f "$CFG_FILE" ]]; then
        source "$CFG_FILE"
    fi
}

save_defaults() {
    cat > "$CFG_FILE" << EOF
ECHO_PASSPHRASE="$ECHO_PASSPHRASE"
ECHO_PORT=$ECHO_PORT
DEFAULT_DSCP=$DEFAULT_DSCP
DEFAULT_DATA_LEN=$DEFAULT_DATA_LEN
DEFAULT_RATE=$DEFAULT_RATE
DEFAULT_INTERVAL="$DEFAULT_INTERVAL"
L2_INTERFACE="$L2_INTERFACE"
VXLAN_INTERFACE="$VXLAN_INTERFACE"
WWAN_INTERFACE="$WWAN_INTERFACE"
L2_ETHER_TYPE="$L2_ETHER_TYPE"
L2_PAYLOAD="$L2_PAYLOAD"
NPING_SERVER_IP="$NPING_SERVER_IP"
IPERF_PORT=$IPERF_PORT
NETEM_DEV="$NETEM_DEV"
NETEM_DELAY="$NETEM_DELAY"
NETEM_JITTER="$NETEM_JITTER"
NETEM_LOSS="$NETEM_LOSS"
EOF
}

# Helper: print header
print_header() {
    clear
    echo "=========================================="
    echo " Raspberry Pi Test Menu - $(date)"
    [[ -n "$ROLE" ]] && echo " Role: $ROLE"
    [[ -n "$TEST_TYPE" ]] && echo " Test: $TEST_TYPE"
    echo "------------------------------------------"
}

# Auto-discover MAC from IP using arping / arp cache
discover_mac() {
    local iface=$1
    local ipaddr=$2
    echo "Attempting to discover MAC for IP $ipaddr on interface $iface..."
    # Send ARP request (ping + arping)
    ping -c 1 -I "$iface" "$ipaddr" &>/dev/null
    if mac=$(arping -c 2 -I "$iface" "$ipaddr" | awk -F '[\\[\\]]' '/Unicast reply from/ {print $2; exit}'); then
        if [[ -n "$mac" ]]; then
            echo "Discovered MAC: $mac"
            echo "$mac"
            return 0
        fi
    fi
    # Fallback: check ARP cache
    mac=$(ip neigh show dev "$iface" | awk -v ip="$ipaddr" '$1==ip && $3!="FAILED" {print $5; exit}')
    if [[ -n "$mac" ]]; then
        echo "Discovered MAC from ARP cache: $mac"
        echo "$mac"
        return 0
    fi
    echo "Failed to discover MAC for $ipaddr"
    return 1
}

# Verify DSCP marking: capture a few packets on given interface matching a filter
verify_dscp() {
    local iface=$1
    local filter_expr=$2
    local duration=$3  # seconds
    echo "Capturing on $iface for $duration seconds to verify DSCP (filter: $filter_expr)..."
    echo "Use Ctrl+C to stop early."
    sudo timeout "$duration" tcpdump -nn -i "$iface" -v "$filter_expr"
    echo "Capture ended."
}

# Configure netem impairment on an interface
configure_netem() {
    echo ""
    read -rp "Enter interface for netem (e.g., $WWAN_INTERFACE, $VXLAN_INTERFACE) [current: $NETEM_DEV]: " iface
    NETEM_DEV=${iface:-$NETEM_DEV}
    if [[ -z "$NETEM_DEV" ]]; then
        echo "No interface specified. Aborting netem setup."
        return
    fi
    read -rp "Enter delay (e.g., 10ms) [current: $NETEM_DELAY]: " d
    NETEM_DELAY=${d:-$NETEM_DELAY}
    read -rp "Enter jitter (e.g., 5ms) [current: $NETEM_JITTER]: " j
    NETEM_JITTER=${j:-$NETEM_JITTER}
    read -rp "Enter loss percentage (e.g., 1%) [current: $NETEM_LOSS]: " l
    NETEM_LOSS=${l:-$NETEM_LOSS}

    # Build netem options
    opts=""
    [[ -n "$NETEM_DELAY" ]] && opts+=" delay $NETEM_DELAY"
    [[ -n "$NETEM_JITTER" ]] && opts+=" $NETEM_JITTER"
    [[ -n "$NETEM_LOSS" ]] && opts+=" loss $NETEM_LOSS"
    if [[ -z "$opts" ]]; then
        echo "No netem parameters given. Aborting."
        return
    fi

    echo "Applying netem on $NETEM_DEV: $opts"
    sudo tc qdisc del dev "$NETEM_DEV" root 2>/dev/null
    sudo tc qdisc add dev "$NETEM_DEV" root netem $opts
    echo "Netem applied."
    save_defaults
}

# Clear netem
clear_netem() {
    echo "Clearing netem on interface. Enter interface (or leave empty to use last: $NETEM_DEV):"
    read -rp "Interface: " iface
    iface=${iface:-$NETEM_DEV}
    if [[ -z "$iface" ]]; then
        echo "No interface specified. Aborting."
        return
    fi
    sudo tc qdisc del dev "$iface" root 2>/dev/null && echo "Cleared netem on $iface."
}

# Iperf3 server/client
run_iperf3_server() {
    read -rp "Enter port for iperf3 server [default: $IPERF_PORT]: " p; IPERF_PORT=${p:-$IPERF_PORT}
    echo "Starting iperf3 server on port $IPERF_PORT..."
    echo "Press Ctrl+C to stop."
    sudo iperf3 -s -p "$IPERF_PORT"
}

run_iperf3_client() {
    read -rp "Enter server IP: " srv
    [[ -z "$srv" ]] && { echo "Server IP cannot be empty."; return; }
    read -rp "Enter port [default: $IPERF_PORT]: " p; PORT=${p:-$IPERF_PORT}
    read -rp "Enter duration in seconds [default: 10]: " dur; dur=${dur:-10}
    read -rp "Enter parallel streams [default: 1]: " pst; pst=${pst:-1}
    read -rp "Enter DSCP value (0-63) [default: $DEFAULT_DSCP]: " dscp; DSCP=${dscp:-$DEFAULT_DSCP}
    echo "Running iperf3 client to $srv:$PORT for $dur s with $pst streams, DSCP=$DSCP..."
    TOS=$(( DSCP << 2 ))
    sudo iperf3 -c "$srv" -p "$PORT" -t "$dur" -P "$pst" -S "$TOS"
}

# Environment check: interfaces, firewall, VXLAN port, reminders
environment_check() {
    echo "--- Environment Check ---"
    echo "Checking interfaces:"
    for iface in "$WWAN_INTERFACE" "$VXLAN_INTERFACE" "$L2_INTERFACE"; do
        if ip link show "$iface" &>/dev/null; then
            echo "  Interface $iface: present"
        else
            echo "  Warning: Interface $iface not found"
        fi
    done
    echo ""
    echo "Checking firewall rules (iptables) for required ports:"
    echo "  - Nping echo port $ECHO_PORT (UDP/TCP):"
    sudo iptables -L -n | grep "$ECHO_PORT" || echo "    No explicit rule for port $ECHO_PORT; ensure traffic allowed."  
    echo "  - iperf3 port $IPERF_PORT (TCP/UDP):"
    sudo iptables -L -n | grep "$IPERF_PORT" || echo "    No explicit rule for port $IPERF_PORT; ensure traffic allowed."  
    echo "  - VXLAN UDP port 4789:"
    sudo iptables -L -n | grep "4789" || echo "    No explicit rule for VXLAN port 4789; ensure allowed."  
    echo ""
    echo "Reminder: Align DSCP values with OAI PDR rules so marked traffic maps to correct 5QI."
    echo "Ensure SMF/UPF configs map DSCP $DEFAULT_DSCP or other chosen values to desired QFI/5QI."  
    echo "Use netem impairments (menu option) on interfaces like $WWAN_INTERFACE or $VXLAN_INTERFACE to simulate link conditions."  
    echo "Combine tests: e.g., run iperf3 bulk low-DSCP and Nping high-DSCP concurrently to observe prioritization."  
    echo "For L2 tests: run L2 echo server/client over VXLAN bridge ($VXLAN_INTERFACE + $L2_INTERFACE) to measure raw frame RTT."  
    echo "--- End Environment Check ---"
    echo "Press any key to continue."; read -n1 -s
}

# Main interactive loop
load_defaults
while true; do
    ROLE=""
    TEST_TYPE=""
    print_header
    echo "Select option:"
    echo " 1) Environment Check"
    echo " 2) Nping Echo Server"
    echo " 3) Nping Echo Client"
    echo " 4) L2 Echo Server"
    echo " 5) L2 Echo Client"
    echo " 6) Iperf3 Server"
    echo " 7) Iperf3 Client"
    echo " 8) Configure Netem Impairment"
    echo " 9) Clear Netem Impairment"
    echo "10) Verify DSCP Marking"
    echo "11) Save Defaults"
    echo "12) Exit"
    read -rp "Enter choice [1-12]: " choice
    case "$choice" in
        1) ROLE="env_check";;
        2) ROLE="nping_server";;
        3) ROLE="nping_client";;
        4) ROLE="l2_server";;
        5) ROLE="l2_client";;
        6) ROLE="iperf3_server";;
        7) ROLE="iperf3_client";;
        8) ROLE="netem_setup";;
        9) ROLE="netem_clear";;
        10) ROLE="dscp_verify";;
        11) save_defaults; echo "Defaults saved to $CFG_FILE."; sleep 1; continue;;
        12) echo "Exiting."; exit 0;;
        *) echo "Invalid choice."; sleep 1; continue;;
    esac

    case "$ROLE" in
    "env_check")
        TEST_TYPE="Environment Check"
        environment_check
        ;;
    "nping_server")
        TEST_TYPE="Nping Echo Server"
        read -rp "Enter echo passphrase [default: $ECHO_PASSPHRASE]: " pp
        ECHO_PASSPHRASE=${pp:-$ECHO_PASSPHRASE}
        read -rp "Enter echo port [default: $ECHO_PORT]: " ep
        ECHO_PORT=${ep:-$ECHO_PORT}
        echo "Starting Nping Echo Server..."
        echo "Press Ctrl+C to stop."
        sudo nping --echo-server "$ECHO_PASSPHRASE" --echo-port "$ECHO_PORT"
        echo "Nping server exited. Press any key."; read -n1 -s
        ;;
    "nping_client")
        TEST_TYPE="Nping Echo Client"
        read -rp "Enter echo server IP [default: $NPING_SERVER_IP]: " sip
        NPING_SERVER_IP=${sip:-$NPING_SERVER_IP}
        if [[ -z "$NPING_SERVER_IP" ]]; then echo "Server IP cannot be empty."; sleep 1; continue; fi
        read -rp "Enter echo passphrase [default: $ECHO_PASSPHRASE]: " pp
        ECHO_PASSPHRASE=${pp:-$ECHO_PASSPHRASE}
        read -rp "Enter echo port [default: $ECHO_PORT]: " ep
        ECHO_PORT=${ep:-$ECHO_PORT}
        echo "Select protocol: 1) ICMP  2) UDP  3) TCP"
        read -rp "Choice [1-3]: " proto_choice
        PROTO_ARGS=""
        case "$proto_choice" in
            1) PROTO_ARGS="--icmp";;
            2) read -rp "Enter destination port [e.g., 5001]: " dp; PROTO_ARGS="--udp -p $dp";;
            3) read -rp "Enter destination port [e.g., 5001]: " dp; PROTO_ARGS="--tcp -p $dp";;
            *) echo "Invalid protocol choice."; sleep 1; continue;;
        esac
        read -rp "Enter data length in bytes [default: $DEFAULT_DATA_LEN]: " dl
        DATA_LEN=${dl:-$DEFAULT_DATA_LEN}
        read -rp "Enter rate (pps) [default: $DEFAULT_RATE]: " rt
        RATE=${rt:-$DEFAULT_RATE}
        read -rp "Enter interval (e.g., 100ms) [default: $DEFAULT_INTERVAL]: " iv
        INTERVAL=${iv:-$DEFAULT_INTERVAL}
        read -rp "Enter DSCP value [default: $DEFAULT_DSCP]: " dscp_in
        DSCP=${dscp_in:-$DEFAULT_DSCP}
        echo "Running Nping Echo Client to $NPING_SERVER_IP..."
        sudo nping --echo-client "$ECHO_PASSPHRASE" "$NPING_SERVER_IP" --echo-port "$ECHO_PORT" \
            $PROTO_ARGS --data-length "$DATA_LEN" --rate "$RATE" --ip-dscp "$DSCP" --interval "$INTERVAL"
        echo "Nping client exited. Press any key."; read -n1 -s
        ;;
    "l2_server")
        TEST_TYPE="L2 Echo Server"
        read -rp "Enter interface to listen on [default: $L2_INTERFACE]: " li
        L2_INTERFACE=${li:-$L2_INTERFACE}
        read -rp "Enter EtherType (hex, e.g., 0x88B5) [default: $L2_ETHER_TYPE]: " et
        L2_ETHER_TYPE=${et:-$L2_ETHER_TYPE}
        echo "Starting L2 Echo Server on $L2_INTERFACE, EtherType $L2_ETHER_TYPE..."
        sudo python3 l2_echo_server.py "$L2_INTERFACE" "$L2_ETHER_TYPE"
        echo "L2 echo server exited. Press any key."; read -n1 -s
        ;;
    "l2_client")
        TEST_TYPE="L2 Echo Client"
        read -rp "Enter interface to send on [default: $L2_INTERFACE]: " li
        L2_INTERFACE=${li:-$L2_INTERFACE}
        echo "Auto-discover destination MAC from IP? (y/n)"
        read -rp "" ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            read -rp "Enter target IP: " target_ip
            if ! DST_MAC=$(discover_mac "$L2_INTERFACE" "$target_ip"); then
                echo "Could not discover MAC; please enter manually."
                read -rp "Enter destination MAC (e.g., aa:bb:cc:dd:ee:ff): " DST_MAC
            fi
        else
            read -rp "Enter destination MAC (e.g., aa:bb:cc:dd:ee:ff): " DST_MAC
        fi
        if [[ -z "$DST_MAC" ]]; then echo "Destination MAC cannot be empty."; sleep 1; continue; fi
        read -rp "Enter EtherType (hex) [default: $L2_ETHER_TYPE]: " et; L2_ETHER_TYPE=${et:-$L2_ETHER_TYPE}
        read -rp "Enter payload (ASCII) [default: $L2_PAYLOAD]: " pl; PAYLOAD=${pl:-$L2_PAYLOAD}
        read -rp "Enter number of packets [default: 10]: " cnt; COUNT=${cnt:-10}
        read -rp "Enter inter-packet delay in seconds (float) [default: 0.1]: " ipd; IPD=${ipd:-0.1}
        echo "Sending $COUNT frames to $DST_MAC over $L2_INTERFACE..."
        sudo python3 l2_echo_client.py "$L2_INTERFACE" "$DST_MAC" "$L2_ETHER_TYPE" "$L2_PAYLOAD" "$COUNT" "$IPD"
        echo "L2 echo client finished. Press any key."; read -n1 -s
        ;;
    "iperf3_server")
        TEST_TYPE="Iperf3 Server"
        run_iperf3_server
        ;;
    "iperf3_client")
        TEST_TYPE="Iperf3 Client"
        run_iperf3_client
        ;;
    "netem_setup")
        TEST_TYPE="Configure Netem"
        configure_netem
        ;;
    "netem_clear")
        TEST_TYPE="Clear Netem"
        clear_netem
        ;;
    "dscp_verify")
        TEST_TYPE="Verify DSCP Marking"
        read -rp "Enter interface to capture on [e.g., $VXLAN_INTERFACE or $WWAN_INTERFACE] [default: $L2_INTERFACE]: " iface
        iface=${iface:-$L2_INTERFACE}
        read -rp "Enter tcpdump filter expression [default: ip]: " filt
        filt=${filt:-ip}
        read -rp "Enter capture duration in seconds [default: 5]: " dur
        dur=${dur:-5}
        verify_dscp "$iface" "$filt" "$dur"
        ;;
    esac
    # After each action, save defaults
    save_defaults
done
