source ~/.bashrc && \
source /opt/ros/${ROS_DISTRO}/setup.bash && \
echo "ROS_DOMAIN_ID $ROS_DOMAIN_ID" && \
echo "Pointcloud enabled: $5" && \
echo "RWM Implementation $RMW_IMPLEMENTATION" && \
ros2 launch realsense2_camera rs_launch.py initial_reset:=true \
                                           enable_rgbd:=true \
                                           enable_sync:=true \
                                           align_depth.enable:=true \
                                           enable_color:=true \
                                           enable_depth:=true \
                                           pointcloud.enable:=$5 \
                                           rgb_camera.color_profile:="$3x$4x30"  \
                                           depth_module.depth_profile:="$3x$4x30" \
                                           depth_module.infra_profile:="$3x$4x30" \
                                           serial_no:="_$1" \
                                           camera_namespace:="$2" \
                                           enable_gyro:=$6 \
                                           enable_accel:=$6 \
                                           unite_imu_method:=linear_interpolation


