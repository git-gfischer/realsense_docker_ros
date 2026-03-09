# realsense docker ROS2 Humble in x86 Machines
This repo builds an docker image to run multiple Intel RealSense cameras with ROS-Humble

## Build Docker Images
Run the following command to build the docker image, the default ros2 version is ```humble``` but you can change by adding the flag ``` --build-arg ROS_DISTRO=jazzy``` for example.
```
sudo docker build -t realsense_ros_docker .
```

## Create an enviroment file
To configure the environment with ROS and Camera parameters, first create the environment with
```
touch <.ENV_NAME>
```

### D435 environment file
Than add the following info for Env file if you are running a D435 camera
```
ROS_DOMAIN_ID=1 
D435_SN=134322074149 (Change this to your camera)
D435_WIDTH=640
D435_HEIGHT=480
D435_NAME=realsense/front
POINTCLOUD=False
IMU=True
```
You can have multiple environment files, one for each camera.

### D405 environment file
Than add the following info for Env file if you are running a D405 camera
```
ROS_DOMAIN_ID=1 
D405_SN=134322074149 (Change this to your camera)
D405_WIDTH=640
D405_HEIGHT=480
D405_NAME=realsense/back
```

## Run Realsense D4XX camera
```
docker compose --env-file <.ENV_FILE> up d4XX -d
```

## Run Realsense D405 camera
```
docker compose --env-file <.ENV_FILE> up d405 -d
```
## Run Enumerate Devices
To check the serial number and other information about the connected cameras, run
```
docker compose run enumerate_devices
```

## Run Realsense-viewer
Run the following to get to realsense-viewer
```
docker compose up realsense-viewer
```

## Run Rviz
To see the images from the Topics
```
xhost +
docker compose run rviz
```

## Collect images
```
docker compose up rgbd_collector
```

## Enter Docker
```
docker compose run enter bash
```
