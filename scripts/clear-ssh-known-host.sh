#!/usr/bin/env bash
# clear-ssh-known-host.sh — clear a stale SSH host key after re-flashing a
# machine's OS at the same IP.
#
# Why this exists: a fresh OS install always generates a new SSH host key.
# If your known_hosts file still has the *old* install's key cached for that
# IP, SSH will correctly refuse to connect with a
# "REMOTE HOST IDENTIFICATION HAS CHANGED" warning until told the change is
# expected. This is routine after any re-flash — not a security incident.
# See debugging-journey.md, Issue #5.
#
# Usage:
#   ./clear-ssh-known-host.sh <pi-ip-or-hostname>

set -euo pipefail

TARGET="${1:?Usage: $0 <pi-ip-or-hostname>}"

echo "Removing cached host key for '$TARGET' from ~/.ssh/known_hosts..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$TARGET"

echo
echo "Done. Reconnect now and accept the new key when prompted:"
echo "  ssh test@$TARGET"
