import os
import datetime
import subprocess
from typing import Optional, List

import rclpy
from rclpy.node import Node
from rclpy.executors import MultiThreadedExecutor
from sensor_msgs.msg import Image, CameraInfo
from std_srvs.srv import Trigger
import message_filters


class RGBDSyncNode(Node):
    def __init__(self) -> None:
        super().__init__("rgbd_sync_node")

        # Parameters for input topics
        self.declare_parameter("color_topic", "/camera/color/image_raw")
        self.declare_parameter("depth_topic", "/camera/depth/image_rect_raw")
        self.declare_parameter("color_info_topic", "/camera/color/camera_info")
        self.declare_parameter("depth_info_topic", "/camera/depth/camera_info")

        color_topic = self.get_parameter("color_topic").get_parameter_value().string_value
        depth_topic = self.get_parameter("depth_topic").get_parameter_value().string_value
        color_info_topic = self.get_parameter("color_info_topic").get_parameter_value().string_value
        depth_info_topic = self.get_parameter("depth_info_topic").get_parameter_value().string_value

        # Subscribers for sync
        self.color_sub = message_filters.Subscriber(self, Image, color_topic)
        self.depth_sub = message_filters.Subscriber(self, Image, depth_topic)
        self.color_info_sub = message_filters.Subscriber(self, CameraInfo, color_info_topic)
        self.depth_info_sub = message_filters.Subscriber(self, CameraInfo, depth_info_topic)

        # Approximate time sync on four topics
        self.ts = message_filters.ApproximateTimeSynchronizer(
            [self.color_sub, self.depth_sub, self.color_info_sub, self.depth_info_sub],
            queue_size=10,
            slop=0.05,
        )
        self.ts.registerCallback(self.sync_callback)

        # Republish synced streams
        self.pub_color = self.create_publisher(Image, "/rgbd_sync/color/image", 10)
        self.pub_depth = self.create_publisher(Image, "/rgbd_sync/depth/image", 10)
        self.pub_color_info = self.create_publisher(CameraInfo, "/rgbd_sync/color/camera_info", 10)
        self.pub_depth_info = self.create_publisher(CameraInfo, "/rgbd_sync/depth/camera_info", 10)

        self.get_logger().info(
            f"RGBDSyncNode started. Syncing {color_topic} & {depth_topic} with camera infos."
        )

    def sync_callback(
        self,
        color_msg: Image,
        depth_msg: Image,
        color_info_msg: CameraInfo,
        depth_info_msg: CameraInfo,
    ) -> None:
        # Republish messages with aligned timestamps
        self.pub_color.publish(color_msg)
        self.pub_depth.publish(depth_msg)
        self.pub_color_info.publish(color_info_msg)
        self.pub_depth_info.publish(depth_info_msg)


class RGBDBagRecorder(Node):
    def __init__(self) -> None:
        super().__init__("rgbd_bag_recorder")

        # Parameters
        self.declare_parameter("output_dir", "/home/rosbags")
        self.declare_parameter(
            "topics",
            [
                "/rgbd_sync/color/image",
                "/rgbd_sync/depth/image",
                "/rgbd_sync/color/camera_info",
                "/rgbd_sync/depth/camera_info",
            ],
        )

        self.output_dir = self.get_parameter("output_dir").get_parameter_value().string_value
        topics_param = self.get_parameter("topics").get_parameter_value().string_array_value
        self.topics: List[str] = list(topics_param)

        os.makedirs(self.output_dir, exist_ok=True)

        self._bag_process: Optional[subprocess.Popen] = None

        # Services (optional manual control, in addition to auto start/stop)
        self.start_srv = self.create_service(Trigger, "start_rgbd_bag", self.start_cb)
        self.stop_srv = self.create_service(Trigger, "stop_rgbd_bag", self.stop_cb)

        self.get_logger().info(
            f"RGBDBagRecorder ready. Output dir: {self.output_dir}, topics: {self.topics}"
        )

        # Automatically start recording when the node comes up
        self._start_bag()

    def _start_bag(self) -> None:
        if self._bag_process is not None and self._bag_process.poll() is None:
            self.get_logger().warn("Bag recording already running, not starting again.")
            return

        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bag_path = os.path.join(self.output_dir, f"rgbd_bag_{timestamp}")

        cmd = ["ros2", "bag", "record", "-o", bag_path] + self.topics
        self.get_logger().info(f"Starting ros2 bag automatically: {' '.join(cmd)}")

        try:
            # Use current env so ROS_DOMAIN_ID etc. propagate
            self._bag_process = subprocess.Popen(cmd, env=os.environ.copy())
        except Exception as exc:
            self._bag_process = None
            self.get_logger().error(f"Failed to start bag recording: {exc}")

    def _stop_bag(self) -> None:
        if self._bag_process is None or self._bag_process.poll() is not None:
            return

        self.get_logger().info("Stopping ros2 bag record...")
        self._bag_process.terminate()

        try:
            self._bag_process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            self.get_logger().warn("ros2 bag did not terminate, killing...")
            self._bag_process.kill()

        self._bag_process = None

    # Service callbacks still available for manual control if desired
    def start_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        if self._bag_process is not None and self._bag_process.poll() is None:
            response.success = False
            response.message = "Bag recording already running."
            return response

        self._start_bag()

        if self._bag_process is not None and self._bag_process.poll() is None:
            response.success = True
            response.message = "Started bag recording."
        else:
            response.success = False
            response.message = "Failed to start bag recording (see logs)."

        return response

    def stop_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        if self._bag_process is None or self._bag_process.poll() is not None:
            response.success = False
            response.message = "No bag recording process running."
            return response

        self._stop_bag()
        response.success = True
        response.message = "Stopped bag recording."
        return response


class RGBDBagPlayer(Node):
    def __init__(self) -> None:
        super().__init__("rgbd_bag_player")

        # Parameters
        self.declare_parameter("input_dir", "/home/rosbags")
        self.declare_parameter("bag_name", "")

        self.input_dir = self.get_parameter("input_dir").get_parameter_value().string_value

        os.makedirs(self.input_dir, exist_ok=True)

        self._play_process: Optional[subprocess.Popen] = None

        # Service: use a parameter 'bag_name' to select which bag to play
        self.play_srv = self.create_service(Trigger, "play_rgbd_bag", self.play_cb)
        self.stop_play_srv = self.create_service(Trigger, "stop_rgbd_bag_play", self.stop_play_cb)

        self.get_logger().info(
            f"RGBDBagPlayer ready. Input dir: {self.input_dir}. "
            f"Set parameter 'bag_name' before calling play_rgbd_bag."
        )

    def _start_play(self, bag_path: str) -> None:
        if self._play_process is not None and self._play_process.poll() is None:
            self.get_logger().warn("Bag play already running, stopping first.")
            self._stop_play()

        cmd = ["ros2", "bag", "play", bag_path]
        self.get_logger().info(f"Starting ros2 bag play: {' '.join(cmd)}")

        try:
            self._play_process = subprocess.Popen(cmd, env=os.environ.copy())
        except Exception as exc:
            self._play_process = None
            self.get_logger().error(f"Failed to start bag play: {exc}")

    def _stop_play(self) -> None:
        if self._play_process is None or self._play_process.poll() is not None:
            return

        self.get_logger().info("Stopping ros2 bag play...")
        self._play_process.terminate()

        try:
            self._play_process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            self.get_logger().warn("ros2 bag play did not terminate, killing...")
            self._play_process.kill()

        self._play_process = None

    def play_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        bag_name_param = self.get_parameter("bag_name").get_parameter_value().string_value
        if not bag_name_param:
            response.success = False
            response.message = "Parameter 'bag_name' is empty. Set it before calling play_rgbd_bag."
            return response

        # Support either a full path or a name relative to input_dir
        if os.path.isabs(bag_name_param):
            bag_path = bag_name_param
        else:
            bag_path = os.path.join(self.input_dir, bag_name_param)

        if not os.path.exists(bag_path):
            response.success = False
            response.message = f"Bag path does not exist: {bag_path}"
            return response

        self._start_play(bag_path)

        if self._play_process is not None and self._play_process.poll() is None:
            response.success = True
            response.message = f"Started playing bag: {bag_path}"
        else:
            response.success = False
            response.message = "Failed to start bag play (see logs)."

        return response

    def stop_play_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        if self._play_process is None or self._play_process.poll() is not None:
            response.success = False
            response.message = "No bag play process running."
            return response

        self._stop_play()
        response.success = True
        response.message = "Stopped bag play."
        return response

def main() -> None:
    rclpy.init(args=None)
    executor = MultiThreadedExecutor()

    sync_node = RGBDSyncNode()
    bag_node = RGBDBagRecorder()
    play_node = RGBDBagPlayer()

    executor.add_node(sync_node)
    executor.add_node(bag_node)
    executor.add_node(play_node)

    try:
        executor.spin()
    finally:
        # Ensure recording is stopped cleanly when the node/container shuts down
        bag_node._stop_bag()
        play_node._stop_play()
        executor.shutdown()
        sync_node.destroy_node()
        bag_node.destroy_node()
        play_node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()

