# ROS 移动机器人学习工作空间

一个基于 **ROS Noetic** 的 catkin 学习 / 演示工作空间，覆盖从「URDF 建模 → Gazebo 仿真 → SLAM 建图 → 自主导航 + 纯追踪（Pure Pursuit）路径跟踪」的完整学习路线。

> 详细的结构说明、依赖关系图和话题数据流，请参见 [`src/PROJECT_OVERVIEW.md`](src/PROJECT_OVERVIEW.md)。

## 目录结构

```
catkin_ws/
├── src/
│   ├── udf01/            # URDF / xacro 机器人建模，RViz + arbotix 控制
│   ├── urdf02_gazebo/    # URDF + Gazebo 仿真，输出 /odom、/scan
│   ├── nav_demo/         # 导航：gmapping 建图、map_server、amcl 定位、move_base
│   └── pp_learning/      # 纯追踪（Pure Pursuit）路径跟踪 + 局部避障
└── README.md
```

## 功能包一览

| 包名 | 主题 | 主要依赖 | 说明 |
|------|------|----------|------|
| `udf01` | URDF 建模 | `urdf` `xacro` | 纯模型包，RViz 显示模型，arbotix 差速控制 |
| `urdf02_gazebo` | Gazebo 仿真 | `gazebo_plugins` `gazebo_ros` `gazebo_ros_control` | 差速驱动 + 激光雷达 + 摄像头插件，输出 `/odom` `/scan` |
| `nav_demo` | 导航 | `gmapping` `map_server` `amcl` `move_base` | 建图、加载地图、定位、全局 + 局部规划 |
| `pp_learning` | 纯追踪 | `roscpp` `nav_msgs` `geometry_msgs` `tf` | 订阅全局路径与定位，计算曲率输出 `/cmd_vel` |

## 环境要求

- **操作系统**：Ubuntu 20.04（Windows 下建议使用 WSL2 或 Docker）
- **ROS 发行版**：Noetic
- **关键依赖包**：

```bash
sudo apt install ros-noetic-urdf ros-noetic-xacro \
                 ros-noetic-gazebo-ros ros-noetic-gazebo-plugins \
                 ros-noetic-gazebo-ros-control ros-noetic-ros-control \
                 ros-noetic-gmapping ros-noetic-map-server ros-noetic-amcl \
                 ros-noetic-move-base ros-noetic-arbotix
```

## 编译

```bash
cd ~/catkin_ws
catkin_make
source devel/setup.bash
```

> 注意：当前顶层 `CMakeLists.txt` 指向 `/opt/ros/noetic/...`（Linux 路径），请在 Linux / WSL 环境编译。若在 Windows 下直接运行需调整路径。

## 快速上手（按学习顺序）

```bash
# 1. URDF 建模显示（RViz 查看模型）
roslaunch udf01 demo03.launch            # 完整车模
roslaunch udf01 demo04_control.launch    # arbotix 差速控制

# 2. Gazebo 仿真（输出 /odom、/scan）
roslaunch urdf02_gazebo demo03_laser.launch

# 3. SLAM 建图（gmapping）
roslaunch nav_demo nav_slam.launch
roslaunch nav_demo nav02_map_save.launch # 保存地图

# 4. 自主导航 + 纯追踪（完整入口）
roslaunch pp_learning self_move_base.launch
```

## 核心设计：纯追踪（Pure Pursuit）路径跟踪

`pp_learning` 是工作空间的最终落脚点，其 `self_move_base.launch` 采用了「规划与控制解耦」的设计：

- move_base 的 `/cmd_vel` 被 `<remap>` 屏蔽到 `dummy_cmd_vel`，只负责全局路径规划；
- 自定义节点 `test815`（完整可用版本）订阅 `/amcl_pose` 与 `/move_base/NavfnROS/plan`，按前视距离 + 曲率公式 `curvature = 2*y / (x²+y²)` 计算并发布真正的 `/cmd_vel`；
- 叠加 `/scan` 前向扇形检测实现简单局部避障。

## 已知问题

详情见 [`src/PROJECT_OVERVIEW.md`](src/PROJECT_OVERVIEW.md) 第 5 节，主要包含：

1. `nav_pure_pursuit.cpp` 计算了控制量但**未调用 publish**（`test815.cpp` 是可用版本）；
2. `urdf02_gazebo/demo01_helloworld.launch` 中 `$(find urfd02_gazebo)` 存在拼写错误；
3. `udf01/demo04_control.launch` 引用了未声明的 `arbotix_python` 依赖；
4. 部分 launch / 地图 YAML 中写死了 `/root/catkin_ws/...` 等绝对路径，需按实际环境调整。
