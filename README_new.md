# RealSense + ROS2 Humble on Jetson AGX Orin (JetPack 6.0)

## Why two steps?

Docker containers **share the host kernel**. The V4L native backend requires patched kernel modules (`uvcvideo`, `videodev`), which must live on the **Jetson host** — not inside the container. Once patched, any container that mounts `/dev` and runs `--privileged` will see the cameras through those modules.

```
Host Jetson                       Docker Container
───────────────────────────────   ───────────────────────────────────────
Patched uvcvideo.ko  ←── shared── librealsense2 (FORCE_RSUSB=false)
/dev/video*          ←── mount ── realsense-ros2 launch files
/run/udev            ←── mount ──
```

---

## Step 1 — Patch the host kernel (once)

Run on the **Jetson board** (not inside Docker):

```bash
chmod +x 00_patch_host_kernel.sh
./00_patch_host_kernel.sh
```

After this, check the output of the following commands:

```bash
modinfo -F filename uvcvideo # expected: /lib/modules/5.15.148-tegra/extra/uvcvideo.ko
modinfo -F filename videodev # expected: /lib/modules/5.15.148-tegra/extra/videodev.ko
```

If those command output match the expectation the patch is in place.

- Takes ~30 minutes (downloads kernel source, applies patches, inserts modules).
- Requires ~2.5 GB free space and internet access.
- Unplug all USB cameras before running.
- No reboot required; modules are inserted live and survive reboots.

---

## Step 2 — Build the Docker image

```bash
docker compose build
# or with explicit args:
docker compose build \
  --build-arg LIBREALSENSE_VERSION=v2.55.1 \
  --build-arg REALSENSE_ROS_VERSION=4.55.1
```

Build time: ~20–40 min (compiles librealsense + realsense-ros from source).

---

## Step 3 — Run

### Interactive shell
```bash
docker compose run realsense_ros2
```

### Single camera
```bash
docker compose run realsense_ros2 \
  ros2 launch realsense2_camera rs_launch.py
```

### Single camera with depth + color streams
```bash
docker compose run realsense_ros2 \
  ros2 launch realsense2_camera rs_launch.py \
    depth_module.profile:=640x480x30 \
    rgb_camera.profile:=640x480x30 \
    enable_color:=true \
    enable_depth:=true
```

### Multi-camera (by serial number)
Find your serial numbers first:
```bash
docker compose run realsense_ros2 rs-enumerate-devices -s
```

Then launch each camera with its serial:
```bash
# Camera 1
docker compose run realsense_ros2 \
  ros2 launch realsense2_camera rs_launch.py \
    serial_no:="_123456789" camera_namespace:=cam1 &

# Camera 2
docker compose run realsense_ros2 \
  ros2 launch realsense2_camera rs_launch.py \
    serial_no:="_987654321" camera_namespace:=cam2
```

### View topics
```bash
# From another terminal (or same container shell)
ros2 topic list
ros2 topic echo /camera/color/image_raw/compressed
```

---

## Common launch parameters

| Parameter | Default | Description |
|---|---|---|
| `serial_no` | `""` (first found) | Camera serial, prefix with `_` |
| `camera_name` | `camera` | ROS node name |
| `camera_namespace` | `camera` | Topic namespace |
| `enable_depth` | `true` | Enable depth stream |
| `enable_color` | `true` | Enable RGB stream |
| `enable_infra1` | `false` | Left IR stream |
| `enable_infra2` | `false` | Right IR stream |
| `depth_module.profile` | `640x480x30` | `WxHxFPS` |
| `rgb_camera.profile` | `640x480x30` | `WxHxFPS` |
| `pointcloud.enable` | `false` | Enable point cloud topic |
| `align_depth.enable` | `false` | Align depth to color frame |

---

## Troubleshooting

### No device found
```
[ERROR] RealSenseNode - No device found
```
- Verify the camera is detected on the host: `lsusb | grep Intel`
- Check the V4L device exists: `ls /dev/video*`
- Confirm kernel modules are loaded: `lsmod | grep uvcvideo`
- Re-run `00_patch_host_kernel.sh` if modules are missing.

### Permission denied on /dev/video*
The container must run with `privileged: true` (set in docker-compose.yml).
Alternatively: `--device /dev/video0 --device /dev/video1 ...`

### CUDA not detected
```
[WARN] CUDA is not available
```
Verify the CUDA toolkit is visible inside the container:
```bash
docker compose run realsense_ros2 nvcc --version
```
If missing, ensure the base image tag matches your JetPack version.
Update `L4T_VERSION` in `docker-compose.yml` (`r36.3.0` = JetPack 6.0).

### rviz2 / display forwarding
On the Jetson host, allow Docker to connect to X:
```bash
xhost +local:docker
```
Then launch rviz2 from inside the container normally.

---

## Version matrix

| Component | Version |
|---|---|
| JetPack | 6.0 |
| L4T | r36.3.0 |
| Ubuntu (base) | 22.04 |
| CUDA | 12.x (from JetPack) |
| ROS2 | Humble |
| librealsense2 | v2.55.1 |
| realsense-ros | 4.55.1 |
