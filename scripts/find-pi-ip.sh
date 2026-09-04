#!/usr/bin/env bash
# find-pi-ip.sh — locate the Pi's current IP after a DHCP reassignment.
#
# Why this exists: after `sudo reboot` on the Pi, SSH can fail with
# "No route to host" rather than a timeout — that specific error means DHCP
# handed the Pi a *different* IP than before, not that it's slow to boot.
# See debugging-journey.md, Issue #6.
#
# Usage:
#   ./find-pi-ip.sh <subnet>            # e.g. ./find-pi-ip.sh 192.168.1.0/24
#   ./find-pi-ip.sh <subnet> <mac-prefix>
#
# Requires: nmap (sudo apt install -y nmap)

set -euo pipefail

SUBNET="${1:?Usage: $0 <subnet e.g. 192.168.1.0/24> [mac-prefix e.g. b8:27:eb]}"
MAC_PREFIX="${2:-}"   # Raspberry Pi Foundation OUI prefixes: b8:27:eb (older), dc:a6:32 / e4:5f:01 (Pi 4)

echo "Scanning $SUBNET for live hosts (requires sudo for MAC address resolution)..."
echo

if [ -n "$MAC_PREFIX" ]; then
  sudo nmap -sn "$SUBNET" | grep -B2 -i "$MAC_PREFIX" || {
    echo "No host matched MAC prefix '$MAC_PREFIX'. Full scan below:"
    sudo nmap -sn "$SUBNET"
  }
else
  echo "No MAC prefix given — showing all live hosts. Look for one of these"
  echo "Raspberry Pi Foundation OUI prefixes in the output: b8:27:eb, dc:a6:32, e4:5f:01"
  echo
  sudo nmap -sn "$SUBNET"
fi

echo
echo "Alternative (no nmap needed, checks the ARP/neighbor cache instead):"
echo "  ip neigh"
