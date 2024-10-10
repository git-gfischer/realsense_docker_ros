# realsense_docker_ros
This repo builds an docker image to run multiple Intel RealSense cameras with ROS-noetic

## Build Docker Images
```
sudo docker build -t realsense_ros .
```

## Create an enviroment file
To configure the environment with ROS and Camera parameters, first create the environment with
```
touch <.ENV_NAME>
```
Than add the following info
```
ROS_URI=http://localhost:11311
DROS_IP=localhost
D435_SN=134322074149
D435_WIDTH=640
D435_HEIGHT=480
D435_NAME=realsense/front/camera
```
You can have multiple environment files, one for each camera.

## Run Realsense camera
```
sudo docker compose --env-file <.ENV_FILE> up realsense_camera -d
```
