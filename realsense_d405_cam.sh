source ~/.bashrc
source /opt/ros/${ROS_DISTRO}/setup.bash

# rs-enumerate-devices -s prints a header, then one padded line per camera.
# The serial is the only long all-digit field.
single_camera_serial() {
    if ! command -v rs-enumerate-devices >/dev/null 2>&1; then
        echo "rs-enumerate-devices is not available in this container." >&2
        return 1
    fi

    local listing devices count serial
    listing=$(rs-enumerate-devices -s 2>/dev/null)
    devices=$(printf '%s\n' "$listing" | awk 'NR > 1 && $0 !~ /^[[:space:]]*$/ && $0 !~ /No device detected/')
    count=$(printf '%s\n' "$devices" | awk 'NF { c++ } END { print c + 0 }')

    if [ "$count" -eq 0 ]; then
        echo "No RealSense camera detected." >&2
        return 1
    fi
    if [ "$count" -gt 1 ]; then
        echo "More than one RealSense camera is connected. Set D405_SN to choose one:" >&2
        printf '%s\n' "$devices" >&2
        return 1
    fi

    serial=$(printf '%s\n' "$devices" | awk '{
        for (i = 1; i <= NF; i++) if ($i ~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9]*$/) { print $i; exit }
    }')
    if [ -z "$serial" ]; then
        echo "Found one camera, but could not read its serial number:" >&2
        printf '%s\n' "$devices" >&2
        return 1
    fi

    echo "Using the only connected camera:" >&2
    printf '%s\n' "$devices" >&2
    printf '%s\n' "$serial"
}

SN="$1"
if [ -z "$SN" ]; then
    echo "D405_SN is empty. Checking connected RealSense cameras..."
    SN=$(single_camera_serial) || exit 1
fi

echo "ROS_DOMAIN_ID $ROS_DOMAIN_ID"
echo "Camera serial: $SN"
echo "RMW Implementation $RMW_IMPLEMENTATION"
ros2 launch realsense2_camera rs_launch.py initial_reset:=true \
                                            enable_sync:=true \
                                            align_depth.enable:=true \
                                            enable_color:=true \
                                            enable_depth:=true \
                                            rgb_camera.color_profile:="$3x$4x30" \
                                            depth_module.depth_profile:="$3x$4x30" \
                                            serial_no:="_$SN" \
                                            camera_namespace:=${D405_NAME}
