# realsense_docker_ros
This repo builds an docker image to run multiple Intel RealSense cameras with ROS framework. </br>
The repo is divided in branches for each ROS distribution and the Operating System. </br>
Change the branch to have access to the docker image installation process

# ROS-noetic x86
``` git checkout noetic_x86```

# ROS-humble x86
``` git checkout humble_x86```


## Build Docker Images
```
sudo docker build -t realsense_ros .
```

## Create an enviroment file
To configure the environment with ROS and Camera parameters, first create the environment with
```
touch <.ENV_NAME>
```

### D435 environment file
Than add the following info for Env file if you are running a D435 camera
```
ROS_URI=http://localhost:11311
DROS_IP=localhost
D435_SN=134322074149 (Change this to your camera)
D435_WIDTH=640
D435_HEIGHT=480
D435_NAME=realsense/front/camera
POINTCLOUD=False
```
You can have multiple environment files, one for each camera.

### t265 environment file
Than add the following info for Env file if you are running a D435 camera
```
ROS_URI=http://localhost:11311
DROS_IP=localhost
T265_SN=134322074149 (change this to your camera)
T265_NAME=camera
```

### D405 environment file
Than add the following info for Env file if you are running a D405 camera
```
ROS_URI=http://localhost:11311
DROS_IP=localhost
D405_SN=134322074149 (Change this to your camera)
D405_WIDTH=640
D405_HEIGHT=480
D405_NAME=realsense/back/camera 
```

## Run Realsense D435 camera
```
sudo docker compose --project_name <NAME> --env-file <.ENV_FILE> up d435 -d
```

## Run Realsense T265 camera
```
sudo docker compose --project_name <NAME> --env-file <.ENV_FILE> up t265 -d
```
## Run Realsense D405 camera

```
sudo docker compose --project_name <NAME> --env-file <.ENV_FILE> up d405 -d
```
## Run Enumerate Devices
To check the serial number and other information about the connected cameras, run
```
sudo docker compose run enumerate_devices
```
