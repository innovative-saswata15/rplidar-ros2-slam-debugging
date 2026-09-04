#!/usr/bin/env bash
# verify-slam-params.sh — confirm a params file actually loaded on the live
# node, instead of trusting that "edit the file + relaunch" worked.
#
# Why this exists: this was the single biggest time-sink of the whole
# debugging session (debugging-journey.md, Issue #10). `ros2 launch` had
# been silently failing to load a custom YAML the entire time, so every edit
# made to it was never actually applied — the node kept running on its
# compiled-in defaults. Running this check after every relaunch would have
# caught that on the very first attempt.
#
# Usage:
#   ./verify-slam-params.sh
#   ./verify-slam-params.sh /costmap/costmap   # check a different node

set -euo pipefail

NODE="${1:-/slam_toolbox}"

echo "== Checking live parameters on $NODE =="
echo

for param in base_frame odom_frame map_frame scan_topic map_update_interval \
             minimum_travel_distance minimum_travel_heading; do
  value=$(ros2 param get "$NODE" "$param" 2>&1) || value="(not set on this node)"
  printf "  %-28s %s\n" "$param" "$value"
done

echo
echo "If any of these don't match what's in your YAML file, the params file"
echo "isn't actually loading. Try running the node directly instead of via"
echo "'ros2 launch' — it will surface a 'Couldn't parse params file' error"
echo "that the launch wrapper may be swallowing silently:"
echo
echo "  ros2 run slam_toolbox async_slam_toolbox_node --ros-args --params-file <path>"
