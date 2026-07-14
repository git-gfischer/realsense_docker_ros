
ROS_DOMAIN_ID=55
RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
D435_SN=941322072804
D435_WIDTH=640
D435_HEIGHT=480
D435_FPS=30
D435_NAME=realsense/front/camera
POINTCLOUD=False

source /ros2_ws/install/setup.bash && \
echo "RWM IMPLEMENTATION $RMW_IMPLEMENTATION"
export RMW_IMPLEMENTATION=$RMW_IMPLEMENTATION
export ROS_DOMAIN_ID=$ROS_DOMAIN_ID

ros2 launch realsense2_camera rs_launch.py initial_reset:=true \
                                           enable_color:=true \
                                           enable_depth:=true \
                                           enable_infra:=true \
                                           enable_rgbd:=true \
                                           enable_sync:=true \
                                           align_depth.enable:=true \
                                           rgb_camera.color_profile:=${D435_WIDTH}x${D435_HEIGHT}x${D435_FPS} \
                                           depth_module.depth_profile:=${D435_WIDTH}x${D435_HEIGHT}x${D435_FPS} \
                                           depth_module.infra_profile:=${D435_WIDTH}x${D435_HEIGHT}x${D435_FPS} \
                                           pointcloud.enable:=${POINTCLOUD} \
                                           serial_no:="_${D435_SN}" \
                                           camera_namespace:=${D435_NAME} \
                                           pointcloud.stream_filter:=0 \
                                           pointcloud.allow_no_texture_points:=false \
                                           rgb_camera.enable_auto_exposure:=false
                                        #    pointcloud.ordered_pc:=false
# ros2 run realsense2_camera realsense2_camera_node --ros-args -p pointcloud.enable:=false \
#                                                              -p enable_rgbd:=true \
#                                                              -p enable_sync:=true \
#                                                              -p align_depth.enable:=true \
#                                                              -p initial_reset:=true \
#                                                              -p enable_rgbd:=true \
#                                                              -p enable_color:=true \
#                                                              -p enable_depth:=true \
#                                                             -p rgb_camera.color_profile:=640x480x15 \
#                                                             -p depth_module.depth_profile:=640x480x15 \
#                                                             -p depth_module.infra_profile:=640x480x15 \
#                                                             -p camera_namespace:=realsense/front/
                                                            #-p serial_no:="_$1" \
                                                            #-p pointcloud.stream_filter:=RS2_STREAM_COLOR \
                                                            #-p poincloud.allow_no_texture_points:=true \
                                                            #-p pointcloud.ordered_pc:=false
