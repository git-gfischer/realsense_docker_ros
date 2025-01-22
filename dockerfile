FROM osrf/ros:humble-desktop

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update 
# RUN apt-get full-upgrade -y

# Utils
RUN apt-get install -y git wget nano sudo gawk vim iputils-ping ssh byobu software-properties-common micro curl apt-transport-https tmux

# Dependencies
RUN apt-get install -y python3-opencv ca-certificates python3-dev ninja-build \
	dirmngr gnupg2 build-essential python3-pip python3-yaml python3-tk python3-venv gnupg

RUN mkdir -p /etc/apt/keyrings && \
    curl -sSf https://librealsense.intel.com/Debian/librealsense.pgp | tee /etc/apt/keyrings/librealsense.pgp > /dev/null

RUN apt install -y apt-transport-https
RUN echo "deb [signed-by=/etc/apt/keyrings/librealsense.pgp] https://librealsense.intel.com/Debian/apt-repo $(lsb_release -cs) main" > /etc/apt/sources.list.d/librealsense.list
RUN apt-get update && apt-get install -y librealsense2-dkms librealsense2-utils librealsense2-dbg librealsense2-dev


# install ros packages
RUN apt install -y libudev-dev pkg-config libgtk-3-dev
RUN apt install -y libusb-1.0-0-dev pkg-config
RUN apt install -y libglfw3-dev
RUN apt install -y libssl-dev
RUN apt-get install -y libglfw3-dev libgl1-mesa-dev libglu1-mesa
RUN apt-get update && apt-get install -y ros-humble-realsense2-* ros-humble-librealsense2*  ros-humble-realsense2-camera

RUN apt-get update \
 && apt-get install -y \
    ros-humble-rviz2 \
 && rm -rf /var/lib/apt/lists/*

COPY ./realsense_d435_cam.sh /home/realsense_d435_cam.sh
COPY ./realsense_d405_cam.sh /home/realsense_d405_cam.sh


#install image pipeline 
# WORKDIR /home
# RUN mkdir -p ros2_ws/src
# WORKDIR /home/ros2_ws/src
# RUN git clone https://github.com/ros-perception/image_pipeline.git
# RUN bash /opt/ros/humble/setup.bash && colcon build

RUN echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
#RUN echo "source /home/ros2_ws/install/local_setup.bash" >> ~/.bashrc
