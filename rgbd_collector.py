import os
import datetime
import signal
import subprocess
import threading
from typing import Optional, List

import cv2
import numpy as np
import rclpy
from rclpy.node import Node
from rclpy.executors import MultiThreadedExecutor
from sensor_msgs.msg import Image, CameraInfo
from std_srvs.srv import Trigger
import message_filters

OUTPUT_DIR = "/home/rosbags"
# Used until enough frames arrive to measure the rate. RealSense launches at 30.
DEFAULT_FPS = 30


def slam_dataset_requested() -> bool:
    value = os.environ.get("SAVE_SLAM_DATASET", "false").strip().lower()
    return value in {"1", "true", "yes", "on"}


def stamp_to_sec(stamp) -> float:
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def format_stamp(stamp_sec: float) -> str:
    return f"{stamp_sec:.6f}"


def _image_array(msg: Image) -> np.ndarray:
    encoding = msg.encoding.lower()
    if encoding in ("rgb8", "bgr8"):
        channels, dtype = 3, np.uint8
    elif encoding in ("rgba8", "bgra8"):
        channels, dtype = 4, np.uint8
    elif encoding == "mono8":
        channels, dtype = 1, np.uint8
    elif encoding in ("16uc1", "mono16"):
        channels, dtype = 1, np.uint16
    elif encoding == "32fc1":
        channels, dtype = 1, np.float32
    else:
        raise ValueError(f"unsupported image encoding '{msg.encoding}'")

    itemsize = np.dtype(dtype).itemsize
    step = msg.step if msg.step else msg.width * channels * itemsize
    if step % itemsize != 0:
        raise ValueError(f"image step {msg.step} is not aligned for {msg.encoding}")
    row_elems = step // itemsize
    raw = np.frombuffer(msg.data, dtype=dtype)
    count = msg.height * row_elems
    if raw.size < count:
        raise ValueError(f"image data is short for {msg.width}x{msg.height} {msg.encoding}")

    if channels == 1:
        image = raw[:count].reshape(msg.height, row_elems)[:, : msg.width].copy()
    else:
        if row_elems % channels != 0:
            raise ValueError(f"image step {msg.step} does not match {msg.encoding}")
        image = raw[:count].reshape(msg.height, row_elems // channels, channels)[:, : msg.width, :].copy()

    if msg.is_bigendian and itemsize > 1:
        image = image.byteswap()
    return image


def color_for_png(msg: Image) -> np.ndarray:
    image = _image_array(msg)
    encoding = msg.encoding.lower()
    if encoding == "rgb8":
        return cv2.cvtColor(image, cv2.COLOR_RGB2BGR)
    if encoding == "rgba8":
        return cv2.cvtColor(image, cv2.COLOR_RGBA2BGR)
    if encoding == "bgra8":
        return cv2.cvtColor(image, cv2.COLOR_BGRA2BGR)
    if encoding in ("bgr8", "mono8"):
        return image
    raise ValueError(f"unsupported color encoding '{msg.encoding}'")


def depth_millimeters(msg: Image) -> np.ndarray:
    image = _image_array(msg)
    encoding = msg.encoding.lower()
    if encoding in ("16uc1", "mono16"):
        return image
    if encoding == "32fc1":
        meters = np.nan_to_num(image, nan=0.0, posinf=0.0, neginf=0.0)
        return np.clip(np.rint(meters * 1000.0), 0, 65535).astype(np.uint16)
    raise ValueError(f"unsupported depth encoding '{msg.encoding}'")


def _fmt(value: float) -> str:
    return f"{float(value):.8f}".rstrip("0").rstrip(".")


def _coeff(values, index: int) -> float:
    if index < len(values):
        return float(values[index])
    return 0.0


def _baseline_meters(color_info: CameraInfo, depth_info: CameraInfo, fx: float) -> Optional[float]:
    if abs(fx) < 1e-9:
        return None
    for info in (depth_info, color_info):
        if len(info.p) >= 4 and abs(float(info.p[3])) > 1e-6:
            return abs(float(info.p[3]) / fx)
    return None


def camera_yaml(color_info: CameraInfo, depth_info: CameraInfo, fps: int, rgb: bool) -> str:
    k = list(color_info.k)
    fx, fy, cx, cy = float(k[0]), float(k[4]), float(k[2]), float(k[5])
    distortion = list(color_info.d)
    model = color_info.distortion_model.lower()
    fisheye = model in {"equidistant", "kannala_brandt", "kannalabrandt8"}
    baseline = _baseline_meters(color_info, depth_info, fx)
    if baseline is None:
        baseline = 0.05

    lines = [
        "%YAML:1.0",
        "",
        "#--------------------------------------------------------------------------------------------",
        "# Camera Parameters. Generated from color camera_info.",
        "#--------------------------------------------------------------------------------------------",
        'File.version: "1.0"',
        "",
        f'Camera.type: "{"KannalaBrandt8" if fisheye else "PinHole"}"',
        "",
        f"Camera1.fx: {_fmt(fx)}",
        f"Camera1.fy: {_fmt(fy)}",
        f"Camera1.cx: {_fmt(cx)}",
        f"Camera1.cy: {_fmt(cy)}",
        "",
        f"Camera1.k1: {_fmt(_coeff(distortion, 0))}",
        f"Camera1.k2: {_fmt(_coeff(distortion, 1))}",
    ]
    if fisheye:
        lines.extend(
            [
                f"Camera1.k3: {_fmt(_coeff(distortion, 2))}",
                f"Camera1.k4: {_fmt(_coeff(distortion, 3))}",
            ]
        )
    else:
        lines.extend(
            [
                f"Camera1.p1: {_fmt(_coeff(distortion, 2))}",
                f"Camera1.p2: {_fmt(_coeff(distortion, 3))}",
                f"Camera1.k3: {_fmt(_coeff(distortion, 4))}",
            ]
        )
    lines.extend(
        [
            "",
            f"Camera.width: {int(color_info.width)}",
            f"Camera.height: {int(color_info.height)}",
            "",
            f"Camera.fps: {int(fps)}",
            "",
            "# Color order of the images (0: BGR, 1: RGB. It is ignored if images are grayscale)",
            f"Camera.RGB: {1 if rgb else 0}",
            "",
            "# Close/Far threshold. Baseline times.",
            "Stereo.ThDepth: 40.0",
            f"Stereo.b: {_fmt(baseline)}",
            "",
            "# 16-bit depth PNGs are millimeters",
            "RGBD.DepthMapFactor: 1000.0",
            "",
            "#--------------------------------------------------------------------------------------------",
            "# ORB Parameters",
            "#--------------------------------------------------------------------------------------------",
            "ORBextractor.nFeatures: 1250",
            "ORBextractor.scaleFactor: 1.2",
            "ORBextractor.nLevels: 8",
            "ORBextractor.iniThFAST: 20",
            "ORBextractor.minThFAST: 7",
            "",
            "#--------------------------------------------------------------------------------------------",
            "# Viewer Parameters",
            "#--------------------------------------------------------------------------------------------",
            "Viewer.KeyFrameSize: 0.05",
            "Viewer.KeyFrameLineWidth: 1.0",
            "Viewer.GraphLineWidth: 0.9",
            "Viewer.PointSize: 2.0",
            "Viewer.CameraSize: 0.08",
            "Viewer.CameraLineWidth: 3.0",
            "Viewer.ViewpointX: 0.0",
            "Viewer.ViewpointY: -0.7",
            "Viewer.ViewpointZ: -3.5",
            "Viewer.ViewpointF: 500.0",
            "",
        ]
    )
    return "\n".join(lines)


class SlamDatasetWriter:
    def __init__(self, output_dir: str, logger) -> None:
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        self.root = os.path.join(output_dir, f"slam_dataset_{timestamp}")
        self.rgb_dir = os.path.join(self.root, "rgb")
        self.depth_dir = os.path.join(self.root, "depth")
        os.makedirs(self.rgb_dir, exist_ok=True)
        os.makedirs(self.depth_dir, exist_ok=True)

        self._logger = logger
        self._lock = threading.Lock()
        self._rgb_txt = open(os.path.join(self.root, "rgb.txt"), "w", buffering=1)
        self._depth_txt = open(os.path.join(self.root, "depth.txt"), "w", buffering=1)
        self._association_txt = open(os.path.join(self.root, "association.txt"), "w", buffering=1)
        self._rgb_txt.write("# color images\n# timestamp filename\n")
        self._depth_txt.write("# depth images\n# timestamp filename\n")

        self._count = 0
        self._first_stamp: Optional[float] = None
        self._last_stamp: Optional[float] = None
        self._fps = DEFAULT_FPS
        self._camera_info: Optional[tuple] = None
        self._closed = False
        self._logger.info(f"SLAM dataset directory: {self.root}")

    def write(
        self,
        color_msg: Image,
        depth_msg: Image,
        color_info_msg: CameraInfo,
        depth_info_msg: CameraInfo,
    ) -> None:
        with self._lock:
            if self._closed:
                return
            try:
                self._write_frame(color_msg, depth_msg, color_info_msg, depth_info_msg)
            except Exception as exc:
                self._logger.error(f"Failed to save SLAM dataset frame: {exc}")

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            try:
                if self._count >= 2 and self._first_stamp is not None and self._last_stamp is not None:
                    duration = self._last_stamp - self._first_stamp
                    if duration > 1e-6:
                        self._fps = max(1, int(round((self._count - 1) / duration)))
                if self._camera_info is not None:
                    self._write_camera_file()
            finally:
                self._rgb_txt.close()
                self._depth_txt.close()
                self._association_txt.close()
            self._logger.info(
                f"SLAM dataset closed: {self._count} frames, Camera.fps: {self._fps}, path: {self.root}"
            )

    def _write_frame(
        self,
        color_msg: Image,
        depth_msg: Image,
        color_info_msg: CameraInfo,
        depth_info_msg: CameraInfo,
    ) -> None:
        if self._camera_info is None:
            self._camera_info = (
                color_info_msg,
                depth_info_msg,
                color_msg.encoding.lower() != "mono8",
            )
            self._write_camera_file()

        color = color_for_png(color_msg)
        depth = depth_millimeters(depth_msg)
        rgb_stamp = stamp_to_sec(color_msg.header.stamp)
        depth_stamp = stamp_to_sec(depth_msg.header.stamp)
        rgb_name = f"{format_stamp(rgb_stamp)}.png"
        depth_name = f"{format_stamp(depth_stamp)}.png"

        if not cv2.imwrite(os.path.join(self.rgb_dir, rgb_name), color):
            raise RuntimeError(f"failed to write {rgb_name}")
        if not cv2.imwrite(os.path.join(self.depth_dir, depth_name), depth):
            raise RuntimeError(f"failed to write {depth_name}")

        self._rgb_txt.write(f"{format_stamp(rgb_stamp)} rgb/{rgb_name}\n")
        self._depth_txt.write(f"{format_stamp(depth_stamp)} depth/{depth_name}\n")
        self._association_txt.write(
            f"{format_stamp(rgb_stamp)} rgb/{rgb_name} "
            f"{format_stamp(depth_stamp)} depth/{depth_name}\n"
        )

        if self._first_stamp is None:
            self._first_stamp = rgb_stamp
        self._last_stamp = rgb_stamp
        self._count += 1
        if self._count == 1 or self._count % 30 == 0:
            self._logger.info(f"Saved {self._count} SLAM dataset frames to {self.root}")

    def _write_camera_file(self) -> None:
        color_info, depth_info, rgb = self._camera_info
        fx = float(color_info.k[0])
        if _baseline_meters(color_info, depth_info, fx) is None and not getattr(self, "_baseline_warned", False):
            self._baseline_warned = True
            self._logger.warning("camera_info has no stereo baseline; Stereo.b set to 0.05 m")
        path = os.path.join(self.root, "camera.yaml")
        with open(path, "w") as camera_file:
            camera_file.write(camera_yaml(color_info, depth_info, self._fps, rgb))


class RGBDSyncNode(Node):
    def __init__(self) -> None:
        super().__init__("rgbd_sync_node")
        self._dataset_writer: Optional[SlamDatasetWriter] = None

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

    def set_dataset_writer(self, writer: SlamDatasetWriter) -> None:
        self._dataset_writer = writer

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
        if self._dataset_writer is not None:
            self._dataset_writer.write(color_msg, depth_msg, color_info_msg, depth_info_msg)


class RGBDBagRecorder(Node):
    def __init__(self, auto_start: bool = True) -> None:
        super().__init__("rgbd_bag_recorder")

        # Parameters
        self.declare_parameter("output_dir", OUTPUT_DIR)
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

        # Bag recording stays available, and starts on launch unless a SLAM dataset was requested.
        if auto_start:
            self._start_bag()
        else:
            self.get_logger().info("Rosbag auto-start disabled (SLAM dataset mode).")

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
        self.declare_parameter("input_dir", OUTPUT_DIR)
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

    def _stop(_signum, _frame) -> None:
        if rclpy.ok():
            rclpy.shutdown()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    executor = MultiThreadedExecutor()
    save_dataset = slam_dataset_requested()

    sync_node = RGBDSyncNode()
    writer = SlamDatasetWriter(OUTPUT_DIR, sync_node.get_logger()) if save_dataset else None
    if writer is not None:
        sync_node.set_dataset_writer(writer)
    bag_node = RGBDBagRecorder(auto_start=not save_dataset)
    play_node = RGBDBagPlayer()

    executor.add_node(sync_node)
    executor.add_node(bag_node)
    executor.add_node(play_node)

    try:
        executor.spin()
    finally:
        # Ensure recording is stopped cleanly when the node/container shuts down
        if writer is not None:
            writer.close()
        bag_node._stop_bag()
        play_node._stop_play()
        executor.shutdown()
        sync_node.destroy_node()
        bag_node.destroy_node()
        play_node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()

