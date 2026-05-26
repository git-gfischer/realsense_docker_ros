# =============================================================================
# Dockerfile — Intel RealSense + ROS2 Humble
# Target : Jetson AGX Orin | JetPack 6.0 | L4T r36.3.0
#
# Architecture:
#   - Base    : nvcr.io/nvidia/l4t-jetpack (Ubuntu 22.04 + CUDA 12 + cuDNN)
#   - Stage 1 : System deps + ROS2 Humble
#   - Stage 2 : librealsense2 from source (V4L Native backend + CUDA)
#   - Stage 3 : realsense-ros ROS2 wrapper
#
# PRE-REQUISITE (on Jetson HOST, not here):
#   Run ./00_patch_host_kernel.sh once before building this image.
#   The patched kernel modules live on the host; the container accesses
#   them via --privileged + /dev mount.
# =============================================================================
 
ARG L4T_VERSION=r36.3.0
FROM nvcr.io/nvidia/l4t-jetpack:${L4T_VERSION}
 
# Keep ARG visible after FROM
ARG L4T_VERSION=r36.3.0
 
LABEL maintainer="your-team"
LABEL description="RealSense D-series + ROS2 Humble on Jetson AGX Orin (JetPack 6.0)"
LABEL l4t_version=${L4T_VERSION}
 
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
# Prefer CycloneDDS — more reliable on embedded/Jetson setups
ENV RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
 
# =============================================================================
# Stage 1 — System packages & ROS2 Humble
# =============================================================================
 
# ── Locales ───────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y locales && \
    locale-gen en_US en_US.UTF-8 && \
    update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*
 
# ── Core build & sensor dependencies ─────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build toolchain
    git cmake build-essential ninja-build \
    # librealsense runtime & build deps
    libssl-dev \
    libusb-1.0-0-dev \
    libudev-dev \
    pkg-config \
    libgtk-3-dev \
    v4l-utils \
    # Utilities
    curl gnupg2 lsb-release wget ca-certificates \
    usbutils \
    && rm -rf /var/lib/apt/lists/*
 
# ── ROS2 Humble ───────────────────────────────────────────────────────────────
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) \
      signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
      http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
      > /etc/apt/sources.list.d/ros2.list
 
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python / ROS tooling
    python3-pip \
    python3-colcon-common-extensions \
    python3-colcon-mixin \
    python3-rosdep \
    python3-vcstool \
    python3-flake8-docstrings

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-humble-rmw-cyclonedds-cpp \
    ros-humble-diagnostic-updater \
    ros-humble-image-transport \
    ros-humble-image-transport-plugins \
    ros-humble-cv-bridge \
    ros-humble-rqt \
    ros-humble-rqt-image-view \
    ros-humble-rviz2 \
    && rm -rf /var/lib/apt/lists/*
 
# ── rosdep init (once, best-effort) ──────────────────────────────────────────
RUN rosdep init || true
RUN rosdep update --rosdistro ${ROS_DISTRO}
 
# =============================================================================
# Stage 2 — librealsense2 from source
#           V4L Native backend  (FORCE_RSUSB_BACKEND=false)
#           CUDA acceleration   (BUILD_WITH_CUDA=true)
# =============================================================================
 
ARG LIBREALSENSE_VERSION=v2.55.1
ENV LIBREALSENSE_SOURCE_DIR=/opt/librealsense
 
RUN git clone \
    --depth 1 \
    --branch master \
    https://github.com/IntelRealSense/librealsense.git \
    ${LIBREALSENSE_SOURCE_DIR}
 
WORKDIR ${LIBREALSENSE_SOURCE_DIR}
 
# Setup udev rules inside the container (also needed on host, but harmless here)
RUN ./scripts/setup_udev_rules.sh
 
# Build & install
RUN mkdir build && cd build && \
    cmake .. \
      # Native V4L backend — matches the host's patched kernel modules
      -DFORCE_RSUSB_BACKEND=false \
      # CUDA acceleration (JetPack 6.0 ships CUDA 12.x)
      -DBUILD_WITH_CUDA=true \
      -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_EXAMPLES=false \
      -DBUILD_GRAPHICAL_EXAMPLES=false \
      # Python bindings (useful for quick tests)
      -DBUILD_PYTHON_BINDINGS=true \
    && make -j$(($(nproc)-1)) \
    && make install \
    && ldconfig
 
# =============================================================================
# Stage 3 — realsense-ros ROS2 wrapper
#           Version tag mirrors librealsense: 2.x.y  →  4.x.y
# =============================================================================
 
ARG REALSENSE_ROS_VERSION=4.55.1
ENV ROS2_WS=/ros2_ws
 
WORKDIR ${ROS2_WS}/src
 
RUN git clone \
    --depth 1 \
    --branch ${REALSENSE_ROS_VERSION} \
    https://github.com/IntelRealSense/realsense-ros.git
 
WORKDIR ${ROS2_WS}
 
# Install any missing ROS deps declared by the package
RUN . /opt/ros/${ROS_DISTRO}/setup.sh && \
    apt-get update && \
    rosdep install -y \
      --from-paths src \
      --ignore-src \
      --rosdistro ${ROS_DISTRO} && \
    rm -rf /var/lib/apt/lists/*
 
# Build the workspace
RUN . /opt/ros/${ROS_DISTRO}/setup.sh && \
    colcon build \
      --symlink-install \
      --cmake-args \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_WITH_CUDA=true \
      --packages-select \
        realsense2_camera \
        realsense2_camera_msgs \
        realsense2_description \
      --event-handlers console_direct+
 
# =============================================================================
# Entrypoint & runtime defaults
# =============================================================================
 
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
# Expose ROS2 DDS discovery ports (if not using --network host)
EXPOSE 7400/udp 7401/udp
 
WORKDIR ${ROS2_WS}
 
ENTRYPOINT ["/entrypoint.sh"]
# Default: drop into a sourced bash shell
# Override with e.g.:  docker run ... ros2 launch realsense2_camera rs_launch.py
CMD ["bash"]
