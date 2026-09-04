#!/usr/bin/env python3
"""
pi_lidar_bringup.launch.py — runs on the Raspberry Pi.

Brings up:
  1. The rplidar_ros driver node, publishing /scan in the `laser` frame.
  2. A static odom -> laser transform.

That static transform is a deliberate PLACEHOLDER (identity — this rig has no
wheel encoders), documented at length in docs/debugging-journey.md (Issues #9
and #12) and docs/NEXT_STEPS.md. Once rf2o_laser_odometry is integrated
(NEXT_STEPS.md), this static_transform_publisher node should be REMOVED —
rf2o publishes a real, continuously-updating odom -> laser transform instead,
and running both at once would fight over the same transform.

Before relying on this file working "as-is" on a new machine, re-read
Issue #7 in debugging-journey.md: ROS_DOMAIN_ID must be sourced in the shell
*before* this launch file is run, not after — a running process never picks
up an environment variable set later.

Usage (on the Pi, after `source ~/.bashrc`):
    ros2 launch pi_lidar_bringup.launch.py
"""

from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    rplidar_node = Node(
        package="rplidar_ros",
        executable="rplidar_node",
        name="rplidar_node",
        parameters=[{
            "channel_type": "serial",
            "serial_port": "/dev/ttyUSB0",
            "serial_baudrate": 115200,   # RPLIDAR A1 default
            "frame_id": "laser",
            "inverted": False,
            "angle_compensate": True,
        }],
        output="screen",
    )

    # Placeholder odom -> laser transform (identity). See module docstring —
    # this goes away once rf2o_laser_odometry is wired in (docs/NEXT_STEPS.md).
    odom_to_laser_tf = Node(
        package="tf2_ros",
        executable="static_transform_publisher",
        name="odom_to_laser_placeholder_tf",
        arguments=["0", "0", "0", "0", "0", "0", "odom", "laser"],
        output="screen",
    )

    return LaunchDescription([
        rplidar_node,
        odom_to_laser_tf,
    ])
