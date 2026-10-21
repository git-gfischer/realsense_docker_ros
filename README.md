# realsense docker ROS2 Humble in x86 Machines
This repo builds an docker image to run multiple Intel RealSense cameras with ROS-Humble

## Build Docker Images
Run the following command to build the docker image, the default ros2 version is ```humble``` but you can change by adding the flag ``` --build-arg ROS_DISTRO=jazzy``` for example.
```
docker build -t realsense_ros_docker .
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
D435_SN=
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
docker compose --env-file <.ENV_FILE> up -d d4XX
```

## Run Realsense D405 camera
```
docker compose --env-file <.ENV_FILE> up -d d405
```
## Run Enumerate Devices
To check the serial number and other information about the connected cameras, run
```
docker compose run enumerate_devices
```
If `D4XX_SN` or `D405_SN` is empty and only one RealSense is plugged in, the camera launch runs this check itself and uses that serial. With more than one camera, set the serial in the env file.

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
Records a rosbag of the synced color, depth, and camera info topics into `rosbags/rgbd_bag_<timestamp>/`.
```
docker compose up rgbd_collector
```

To record a SLAM dataset instead of a rosbag, add this to `.ros_env` and run the same command:
```
SAVE_SLAM_DATASET=true
```
That writes `rosbags/slam_dataset_<timestamp>/` with `rgb/`, `depth/` (16-bit millimeters), `rgb.txt`, `depth.txt`, `association.txt`, and `camera.yaml`. The camera file is an ORB-SLAM3 RGB-D settings file, and the intrinsics come from the color `camera_info`. Point ORB-SLAM3 at that folder and `association.txt`. Remove the flag to go back to rosbag recording.

## Enter Docker
```
docker compose run enter bash
```
