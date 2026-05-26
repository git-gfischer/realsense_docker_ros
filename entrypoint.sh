#!/bin/bash
# =============================================================================
# entrypoint.sh
# Sources ROS2 Humble and the realsense-ros workspace, then execs the
# command passed to `docker run` (or drops into bash by default).
# =============================================================================
set -e

# Source ROS2 base
source /opt/ros/humble/setup.bash

# Source the realsense-ros2 workspace
if [ -f /ros2_ws/install/setup.bash ]; then
  source /ros2_ws/install/setup.bash
fi

# Print a brief status banner
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  RealSense ROS2 Container — Jetson AGX Orin               ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ROS_DISTRO : ${ROS_DISTRO}"
echo "║  RMW        : ${RMW_IMPLEMENTATION}"
echo "║  RS version : $(rs-enumerate-devices --version 2>/dev/null | head -1 || echo 'n/a')"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Quick start:"
echo "║    ros2 launch realsense2_camera rs_launch.py"
echo "║    ros2 launch realsense2_camera rs_multi_camera_launch.py"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

exec "$@"
