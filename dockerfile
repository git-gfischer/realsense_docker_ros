# default to $ROS_DISTRO; pass --build-arg ROS_DISTRO=jazzy for Jazzy
ARG ROS_DISTRO=humble

FROM ubuntu:22.04 AS humble_base
FROM ubuntu:24.04 AS jazzy_base
FROM ${ROS_DISTRO}_base AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG ROS_DISTRO
ENV ROS_DISTRO=${ROS_DISTRO}
ENV ROS_ROOT=/opt/ros/${ROS_DISTRO}
ENV ROS_PACKAGE=ros_base

# -------------------------------------------------------------------
# Base packages
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    locales \
    software-properties-common \
    apt-transport-https \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# ROS 2
# -------------------------------------------------------------------
RUN set -e; \
    . /etc/os-release; CODENAME="$VERSION_CODENAME"; \
    case "${ROS_DISTRO}:${CODENAME}" in \
      humble:jammy|jazzy:noble) echo "ROS ${ROS_DISTRO} on ${CODENAME}" ;; \
      *) echo "Unsupported combo: ROS ${ROS_DISTRO} on ${CODENAME}"; exit 1 ;; \
    esac; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      | gpg --dearmor -o /etc/apt/keyrings/ros-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${CODENAME} main" \
      > /etc/apt/sources.list.d/ros2.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-desktop-full \
      python3-rosdep \
      python3-colcon-common-extensions; \
    rosdep init || true; \
    rosdep update || true; \
    echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /etc/bash.bashrc; \
    rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# General dependencies
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-opencv \
    python3-dev \
    python3-pip \
    python3-yaml \
    python3-tk \
    python3-venv \
    ninja-build \
    dirmngr \
    gnupg2 \
    build-essential \
    cmake \
    git \
    wget \
    nano \
    sudo \
    gawk \
    vim \
    iputils-ping \
    ssh \
    byobu \
    micro \
    tmux \
    pkg-config \
    libssl-dev \
    libusb-1.0-0-dev \
    libudev-dev \
    libgtk-3-dev \
    libglfw3-dev \
    libgl1-mesa-dev \
    libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------------------------------------------
# ROS packages that do NOT depend on broken RealSense apt repo setup
# -------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    ros-${ROS_DISTRO}-rviz2 \
    ros-${ROS_DISTRO}-realsense2-camera \
    && rm -rf /var/lib/apt/lists/*

COPY ./realsense_d4XX_cam.sh /home/realsense_d4XX_cam.sh
COPY ./realsense_d405_cam.sh /home/realsense_d405_cam.sh
COPY ./rgbd_collector.py /home/rgbd_collector.py

# -------------------------------------------------------------------
# Build librealsense from source instead of using broken apt repo
# -------------------------------------------------------------------
WORKDIR /opt
RUN git clone --depth=1 https://github.com/realsenseai/librealsense.git && \
    cd librealsense && \
    mkdir build && cd build && \
    cmake .. \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_EXAMPLES=true \
      -DBUILD_GRAPHICAL_EXAMPLES=true \
      -DBUILD_WITH_CUDA=false \
      -DFORCE_RSUSB_BACKEND=true && \
    make -j"$(nproc)" && \
    make install && \
    ldconfig

# Install RealSense udev rules in the image (host rules are still required for USB access)
RUN install -D -m 644 /opt/librealsense/config/99-realsense-libusb.rules \
    /etc/udev/rules.d/99-realsense-libusb.rules

RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc

CMD ["bash"]