#!/usr/bin/env bash

# Defaults — override via positional args or env vars (e.g. from .camera)
SERIAL_NO="${1:-${D405_SN:-}}"
CAMERA_NAMESPACE="${2:-${D405_NAME:-realsense/d405/}}"
WIDTH="${3:-${D405_WIDTH:-640}}"
HEIGHT="${4:-${D405_HEIGHT:-480}}"

source ~/.bashrc && \
source /opt/ros/${ROS_DISTRO}/setup.bash && \
echo "ROS_DOMAIN_ID $ROS_DOMAIN_ID" && \
echo "Serial number: $SERIAL_NO" && \
echo "Camera namespace: $CAMERA_NAMESPACE" && \
echo "Resolution: ${WIDTH}x${HEIGHT}" && \
echo "RWM Implementation $RMW_IMPLEMENTATION" && \
ros2 launch realsense2_camera rs_launch.py initial_reset:=true \
                                           enable_sync:=true \
                                           align_depth.enable:=true \
                                           enable_color:=true \
                                           enable_depth:=true \
                                           rgb_camera.color_profile:="${WIDTH}x${HEIGHT}x30" \
                                           depth_module.depth_profile:="${WIDTH}x${HEIGHT}x30" \
                                           serial_no:="_$SERIAL_NO" \
                                           camera_namespace:="$CAMERA_NAMESPACE"
