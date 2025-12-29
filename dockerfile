# default to $ROS_DISTRO; pass --build-arg ROS_DISTRO=jazzy for Jazzy
ARG ROS_DISTRO=humble

# Predefine base stages per Ubuntu; names must match "<ros>_base" below
# Jammy base for ROS $ROS_DISTRO
FROM ubuntu:22.04 AS humble_base     
# Noble base for ROS Jazzy
FROM ubuntu:24.04 AS jazzy_base      

# Select the right base by ROS_DISTRO ($ROS_DISTRO_base or jazzy_base)
FROM ${ROS_DISTRO}_base AS base

ENV DEBIAN_FRONTEND=noninteractive

# setup environment
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
# Do not delete this following line !!
ARG ROS_DISTRO 
ENV ROS_DISTRO=$ROS_DISTRO
ENV ROS_ROOT=/opt/ros/$ROS_DISTRO
ENV ROS_PACKAGE=ros_base

# Common base setup
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release locales \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*


# Add ROS repo once, verify Ubuntu↔ROS mapping, then install
RUN set -e; \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release locales && \
    locale-gen en_US.UTF-8 && rm -rf /var/lib/apt/lists/*; \
    . /etc/os-release; CODENAME="$VERSION_CODENAME"; \
    case "${ROS_DISTRO}:${CODENAME}" in \
      humble:jammy|jazzy:noble) echo "ROS ${ROS_DISTRO} on ${CODENAME}";; \
      *) echo "Unsupported combo: ROS ${ROS_DISTRO} on ${CODENAME}"; exit 1;; \
    esac; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
      | gpg --dearmor -o /etc/apt/keyrings/ros-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu ${CODENAME} main" \
      > /etc/apt/sources.list.d/ros2.list; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-desktop-full \
      python3-rosdep python3-colcon-common-extensions && \
    rosdep init || true; rosdep update || true; \
    echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /etc/bash.bashrc

RUN apt-get update 
# RUN apt-get full-upgrade -y

# Dependencies
RUN apt-get install -y python3-opencv ca-certificates python3-dev ninja-build \
	dirmngr gnupg2 build-essential python3-pip python3-yaml python3-tk python3-venv gnupg

# Utils
RUN apt update && apt-get install -y git wget nano sudo gawk vim iputils-ping ssh byobu software-properties-common micro curl apt-transport-https tmux

RUN mkdir -p /etc/apt/keyrings && \
    curl -sSf https://librealsense.intel.com/Debian/librealsense.pgp | tee /etc/apt/keyrings/librealsense.pgp > /dev/null

RUN apt install -y apt-transport-https
RUN echo "deb [signed-by=/etc/apt/keyrings/librealsense.pgp] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" > /etc/apt/sources.list.d/librealsense.list
RUN apt-get update && apt-get install -y librealsense2-utils librealsense2-dbg librealsense2-dev


# install ros packages
RUN apt install -y libudev-dev pkg-config libgtk-3-dev
RUN apt install -y libusb-1.0-0-dev pkg-config
RUN apt install -y libglfw3-dev
RUN apt install -y libssl-dev
RUN apt-get install -y libglfw3-dev libgl1-mesa-dev libglu1-mesa
RUN apt-get update && apt-get install -y ros-$ROS_DISTRO-realsense2-* ros-$ROS_DISTRO-librealsense2*  ros-$ROS_DISTRO-realsense2-camera ros-$ROS_DISTRO-rmw-cyclonedds-cpp

RUN apt-get update \
 && apt-get install -y \
    ros-$ROS_DISTRO-rviz2 \
 && rm -rf /var/lib/apt/lists/*

COPY ./realsense_d435_cam.sh /home/realsense_d435_cam.sh
COPY ./realsense_d405_cam.sh /home/realsense_d405_cam.sh



# Install Realsense SDK from source---------------------------------------------------------
# WORKDIR /home
# RUN  apt-key adv --keyserver keyserver.ubuntu.com --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE || apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE 
# RUN  add-apt-repository "deb https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" -u
# RUN  apt-get install -y librealsense2-utils librealsense2-dev

#Clone and build librealsense2
#WORKDIR /opt
#RUN git clone https://github.com/IntelRealSense/librealsense.git  && \
#    cd librealsense && \
#    mkdir build && cd build && \
#    cmake .. -DBUILD_EXAMPLES=true -DBUILD_GRAPHICAL_EXAMPLES=true -DFORCE_LIBUVC=ON -DBUILD_WITH_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=all -DCMAKE_POLICY_VERSION_MINIMUM=3.5 && \
#    make -j$(nproc) && make install && ldconfig
#
#RUN cp /opt/librealsense/config/99-realsense-libusb.rules /etc/udev/rules.d/
#-----------------------------------------------------------------------------------


#install image pipeline 
# WORKDIR /home
# RUN mkdir -p ros2_ws/src
# WORKDIR /home/ros2_ws/src
# RUN git clone https://github.com/ros-perception/image_pipeline.git
# RUN bash /opt/ros/$ROS_DISTRO/setup.bash && colcon build

RUN echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> ~/.bashrc
#RUN echo "source /home/ros2_ws/install/local_setup.bash" >> ~/.bashrc
