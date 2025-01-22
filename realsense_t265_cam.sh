source ~/.bashrc && \
ros2 launch realsense2_camera rs_launch.py serial_no:="_$1" camera_namespace:="$2"