#!/usr/bin/env bash

# Defaults — override via positional args or env vars (e.g. from .camera)
SERIAL_NO="${1:-${D435_SN:-}}"
CAMERA_NAMESPACE="${2:-${D435_NAME:-realsense/front/}}"
WIDTH="${3:-${D435_WIDTH:-640}}"
HEIGHT="${4:-${D435_HEIGHT:-480}}"
POINTCLOUD_ENABLE="${5:-${POINT_CLOUD:-false}}"
IMU_ENABLE="${6:-${IMU:-false}}"

source ~/.bashrc && \
source /opt/ros/${ROS_DISTRO}/setup.bash && \
echo "ROS_DOMAIN_ID $ROS_DOMAIN_ID" && \
echo "Serial number: $SERIAL_NO" && \
echo "Camera namespace: $CAMERA_NAMESPACE" && \
echo "Resolution: ${WIDTH}x${HEIGHT}" && \
echo "Pointcloud enabled: $POINTCLOUD_ENABLE" && \
echo "IMU enabled: $IMU_ENABLE" && \
echo "RWM Implementation $RMW_IMPLEMENTATION" && \
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
                                           unite_imu_method:=linear_interpolation
