#!/usr/bin/env bash

# Defaults — override via positional args or env vars (e.g. from .camera)
SERIAL_NO="${1:-${D435_SN:-}}"
CAMERA_NAMESPACE="${2:-${D435_NAME:-realsense/front/}}"
WIDTH="${3:-${D435_WIDTH:-640}}"
HEIGHT="${4:-${D435_HEIGHT:-480}}"
POINTCLOUD_ENABLE="${5:-${POINT_CLOUD:-false}}"
IMU_ENABLE="${6:-${IMU:-false}}"

source ~/.bashrc
source /opt/ros/${ROS_DISTRO}/setup.bash
set -euo pipefail

echo "ROS_DOMAIN_ID $ROS_DOMAIN_ID"
echo "Serial number: $SERIAL_NO"
echo "Camera namespace: $CAMERA_NAMESPACE"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Pointcloud enabled: $POINTCLOUD_ENABLE"
echo "IMU enabled: $IMU_ENABLE"
echo "RWM Implementation $RMW_IMPLEMENTATION"

CAMERA_NAMESPACE_CLEAN="${CAMERA_NAMESPACE#/}"
CAMERA_NAMESPACE_CLEAN="${CAMERA_NAMESPACE_CLEAN%/}"
CAMERA_NODE="/${CAMERA_NAMESPACE_CLEAN}/camera"

ros2 launch realsense2_camera rs_launch.py initial_reset:=true \
                                           enable_color:=true \
                                           enable_depth:=true \
                                           enable_infra:=true \
                                           enable_rgbd:=true \
                                           enable_sync:=true \
                                           align_depth.enable:=true \
                                           enable_color:=true \
                                           enable_depth:=true \
                                           pointcloud.enable:=$POINTCLOUD_ENABLE \
                                           rgb_camera.color_profile:="${WIDTH}x${HEIGHT}x30" \
                                           depth_module.depth_profile:="${WIDTH}x${HEIGHT}x30" \
                                           depth_module.infra_profile:="${WIDTH}x${HEIGHT}x30" \
                                           serial_no:="_$SERIAL_NO" \
                                           camera_namespace:="$CAMERA_NAMESPACE" \
                                           enable_gyro:=$IMU_ENABLE \
                                           enable_accel:=$IMU_ENABLE \
                                           unite_imu_method:=linear_interpolation &
LAUNCH_PID=$!

if [[ "${POINTCLOUD_ENABLE,,}" == "true" ]]; then
  for _ in $(seq 1 30); do
    if ros2 param get "$CAMERA_NODE" pointcloud__neon_.enable >/dev/null 2>&1; then
      echo "Enabling pointcloud runtime parameter on $CAMERA_NODE"
      ros2 param set "$CAMERA_NODE" pointcloud__neon_.enable true || true
      break
    fi
    sleep 1
  done
fi

wait "$LAUNCH_PID"
