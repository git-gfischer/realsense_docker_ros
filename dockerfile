FROM osrf/ros:noetic-desktop-full

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update 
# RUN apt-get full-upgrade -y

# Utils
RUN apt-get install -y git wget nano sudo gawk vim iputils-ping ssh byobu software-properties-common micro curl apt-transport-https

# Dependencies
RUN apt-get install -y python3-opencv ca-certificates python3-dev ninja-build \
	dirmngr gnupg2 build-essential python3-pip python3-yaml python3-tk python3-venv gnupg

# Setup Realsense libs. We need DKMS(driver). Utils are usefull.
# Alhtought its installed as dependency, the udev is installed in the host, since docker cant modify that
RUN apt update && \
    apt-key adv --keyserver keys.gnupg.net --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE || apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE
RUN add-apt-repository "deb https://librealsense.intel.com/Debian/apt-repo bionic main" -u
RUN apt-get update
RUN apt-get install -y librealsense2-dev librealsense2-dkms librealsense2-utils ros-noetic-ddynamic-reconfigure

# Setup ROS
# setup keys
# RUN apt update && \
#     apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654

RUN sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' && \
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add -

# setup sources.list
RUN echo "deb http://packages.ros.org/ros/ubuntu focal main" > /etc/apt/sources.list.d/ros1-latest.list

# setup environment
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV ROS_DISTRO noetic

# install ros packages
RUN apt-get update && apt-get install -y ros-noetic-realsense2-camera 


# install realsense ros from source
# This is important to use Intel realsense d405 
# WORKDIR /home/ros_ws/src 
# RUN apt-get update && git clone --branch ros1-legacy https://github.com/IntelRealSense/realsense-ros && \
#     sed -i '37d' /home/ros_ws/src/realsense-ros/realsense2_camera/include/realsense2_camera/constants.h && \
#     awk 'NR==37{print "const uint16_t RS405_PID        = 0x0B5B; // DS5U"}1' /home/ros_ws/src/realsense-ros/realsense2_camera/include/realsense2_camera/constants.h > temp.txt && mv temp.txt /home/ros_ws/src/realsense-ros/realsense2_camera/include/realsense2_camera/constants.h
# End Ros Install

#install catkin
RUN apt update && \
    sh -c 'echo "deb http://packages.ros.org/ros/ubuntu `lsb_release -sc` main" > /etc/apt/sources.list.d/ros-latest.list' && \
    wget http://packages.ros.org/ros.key -O - | apt-key add - && \
    apt-get update && \
    apt-get install -y python3-catkin-tools && \
    pip3 install -U catkin_tools

COPY realsense_cam.sh /home/realsense_cam.sh

RUN echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc
RUN echo "export PYTHONPATH=${PYTHONPATH}:/home/ros_ws/.venv/lib/python3.8/site-packages" >> ~/.bashrc
