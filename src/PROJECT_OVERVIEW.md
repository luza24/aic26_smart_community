# 项目总览与使用指南：`nav_demo` 与 `urdf02_gazebo`

> 工作空间：`/root/catkin_ws` · ROS Noetic · Gazebo 11.15.1 · Ubuntu 20.04（WSL2）
> 本文说明这两个包的结构、启动命令、各节点功能、话题/TF 数据流与已知问题。

## 0. 先看分工：两个包各自负责什么

| 包 | 角色 | 提供 | 消费 |
|----|------|------|------|
| `urdf02_gazebo` | **机器人本体 + 仿真世界**（Gazebo 里的“车”和“场地”） | `/odom`、`/scan`、TF `odom→base_footprint`、订阅 `/cmd_vel` | `/cmd_vel`（来自键盘或导航栈） |
| `nav_demo` | **导航大脑**（建图 / 定位 / 路径规划） | `/map`、`/amcl_pose`、TF `map→odom`、全局路径 `/move_base/NavfnROS/plan`、`/cmd_vel` | `/scan`、`/odom` |

一句话：**`urdf02_gazebo` 造出会动的车和激光雷达，`nav_demo` 决定车该往哪走。**
两者之间的接口只有 3 个话题（`/scan`、`/odom`、`/cmd_vel`）和 1 个全局参数（`robot_description`）。

---

## 1. 工作空间总览

```
/root/catkin_ws/
├── README.md                      # 工作空间总说明
├── src/
│   ├── PROJECT_OVERVIEW.md        # ← 本文件
│   ├── udf01/                     # URDF 建模入门（RViz + arbotix，非本文重点）
│   ├── urdf02_gazebo/             # ★ Gazebo 仿真：车模型 + 世界 + 传感器
│   ├── nav_demo/                  # ★ 导航：gmapping / map_server / amcl / move_base
│   └── pp_learning/               # 纯追踪跟踪（消费 nav_demo 的输出，见 §4.5）
├── build/  devel/                 # 编译产物（勿手改）
└── ...
```

编译与生效：

```bash
cd ~/catkin_ws
catkin_make                 # 本工作空间多为 launch/urdf/yaml，改完通常无需重编
source devel/setup.bash     # 每个新终端都要 source
```

> 该工作空间 `find_package` 全在 `package.xml` 中声明，两个包都不含 C++ 源码，
> **修改 `.launch` / `.urdf.xacro` / `.yaml` 后无需重新 `catkin_make`，直接 roslaunch 即可生效。**

---

## 2. `urdf02_gazebo` 详解

### 2.1 包信息

- 依赖：`gazebo_plugins`、`gazebo_ros`、`gazebo_ros_control`、`urdf`、`xacro`
- 无源码节点，纯 URDF/xacro + launch + world

### 2.2 `urdf/` 文件清单与包含关系

| 文件 | 作用 |
|------|------|
| `my_head.urdf.xacro` | **纯宏定义**，不含任何 link：`sphere_inertial_matrix` / `cylinder_inertial_matrix` / `Box_inertial_matrix`（球、圆柱、长方体的惯量矩阵） |
| `demo02_car_base.urdf.xacro` | 小车底盘：`base_footprint`（小球）、`base_link`（圆柱 r=0.1 h=0.08）、左右**驱动轮**（圆柱 r=0.0325 w=0.015，`continuous` 关节，轴 `0 1 0`）、前后**支撑轮**（小球 r=0.0075，轴 `1 1 1`） |
| `demo03_car_camera.urdf.xacro` | 摄像头 link（box 0.01×0.025×0.025），固定关节装在 `base_link` 前上方 |
| `demo04_car_laser.urdf.xacro` | 雷达**支架** `support`（圆柱 r=0.01 h=0.15）+ 雷达**外壳** `laser`（圆柱 r=0.03 h=0.05）。⚠️ **只有几何外形，没有传感器** |
| `laser.urdf.xacro` | ★ 真正的雷达传感器：`<sensor type="ray" name="rplidar">` 挂在 `reference="laser"`，360 线、±3 rad、0.1~30 m、5.5 Hz，插件 `libgazebo_ros_laser.so` → 发布 **`/scan`**，frame = `laser` |
| `my_sensors_camara.urdf.xacro` | 相机传感器（`libgazebo_ros_camera.so` → `/camera/image_raw`），**在 demo06 中被注释掉**，默认不生效 |
| `move.urdf.xacro` | 传动 + 驱动插件：`transmission`（左右轮）+ `libgazebo_ros_diff_drive.so` 差速控制器 → 订阅 `/cmd_vel`、发布 `/odom`、发布 TF |
| `demo05.urdf.xacro` | 组合模型 = head + base + camera + laser(仅外形) + move → **没有 `/scan`** |
| `demo06_laser.urdf.xacro` | 组合模型 = 同 demo05 **+ `laser.urdf.xacro`（真雷达）** → **有 `/scan`** ★ |
| `demo01_helloworld.urdf` | 入门用：一个 0.5×0.2×0.1 的 box 车 `mycar`，无关节无插件 |

包含关系（xacro 相对路径包含，已实测均可正常展开）：

```
demo06_laser.urdf.xacro            demo05.urdf.xacro
├── my_head.urdf.xacro             ├── my_head.urdf.xacro
├── demo02_car_base.urdf.xacro     ├── demo02_car_base.urdf.xacro
├── demo03_car_camera.urdf.xacro   ├── demo03_car_camera.urdf.xacro
├── demo04_car_laser.urdf.xacro    ├── demo04_car_laser.urdf.xacro
├── move.urdf.xacro                └── move.urdf.xacro
└── laser.urdf.xacro  ★有传感器      （无激光传感器）
```

### 2.3 差速驱动插件的关键参数（`move.urdf.xacro`）

| 参数 | 值 | 含义 |
|------|-----|------|
| `leftJoint` / `rightJoint` | `left_wheel2base_link` / `right_wheel2base_link` | 被控关节 |
| `wheelSeparation` | `${base_link_radius*2}` = **0.2 m** | 轮距 |
| `wheelDiameter` | `${wheel_radius*2}` = **0.065 m** | 轮径 |
| `commandTopic` | `cmd_vel` | 订阅的**速度指令**话题 |
| `odometryTopic` / `odometryFrame` | `odom` / `odom` | 里程计话题与坐标系 |
| `robotBaseFrame` | `base_footprint` | 机器人基坐标系 |
| `publishTf` = 1 | — | 发布 TF `odom→base_footprint` |
| `publishWheelTF` = true | — | 发布车轮 TF |
| `publishWheelJointState` = true | — | 发布 `/joint_states` |
| `wheelTorque` / `wheelAcceleration` | 30 / 1.8 | 力矩与加速度限制 |

> `rosDebugLevel`、`alwaysOn`、`broadcastTF` 这几个标签在当前 Noetic 版插件里已不被识别（实测 `strings` 该 `.so` 无对应参数），写了也只是被忽略，无副作用。

### 2.4 `launch/` 对照表 —— ★ 选错 launch 会没有 `/scan`

| launch 文件 | 加载的模型 | world | 有 `/odom` | 有 `/scan` | 用途 |
|-------------|-----------|-------|-----------|-----------|------|
| `demo01_helloworld.launch` | `demo01_helloworld.urdf` | 空世界 | ❌ | ❌ | 入门（**且该文件有拼写 bug，见 §5**） |
| `demo02_car.launch` | `demo05.urdf.xacro` | `hello.world` | ✅ | ❌ | 看模型 + 手动开车 |
| `my_car.launch` | `demo05.urdf.xacro` | `hello.world` | ✅ | ❌ | **与 `demo02_car.launch` 实质完全相同**（仅注释/空白差异） |
| **`demo03_laser.launch`** | **`demo06_laser.urdf.xacro`** | `hello.world` | ✅ | ✅ | ★ **建图 / 导航就用这个** |
| `rviz.launch` | —— | —— | —— | —— | 只起 rviz + JSP + RSP（**不加载模型**，见 §5） |

### 2.5 启动命令与启动后的节点

```bash
source ~/catkin_ws/devel/setup.bash
roslaunch urdf02_gazebo demo03_laser.launch          # ★ 日常用这条
# 无图形界面 / 远程 WSL 加速：
roslaunch urdf02_gazebo demo03_laser.launch gui:=false
```

这条命令做了三件事：

1. `<param name="robot_description" command="xacro ...demo06_laser.urdf.xacro"/>`
   → 把模型以 URDF 文本写到**全局参数服务器** `robot_description`（其它包依赖此参数，见 §4.1）
2. `<include file="$(find gazebo_ros)/launch/empty_world.launch">` + `world_name:=hello.world`
   → 启动 `gzserver`（物理引擎 + 插件）与 `gzclient`（GUI）
3. `<node pkg="gazebo_ros" type="spawn_model" args="-urdf -model mycar -param robot_description"/>`
   → 把车生成到世界里，模型名 `mycar`，初始位姿 (0,0,0)

启动后 `rosnode list` 大致可见：

| 节点 | 功能 |
|------|------|
| `/gazebo` | Gazebo 服务端，承载物理仿真与所有 `<plugin>` / `<sensor>` |
| `/gazebo_gui` | Gazebo 图形界面（`gui:=false` 时不存在） |
| `/spawn_model` | 生成完模型后退出 |
| `/differential_drive_controller`（插件，非独立节点） | 订阅 `/cmd_vel` → 驱动左右轮 → 发布 `/odom` + TF `odom→base_footprint` |
| `/gazebo_rplidar`（插件，非独立节点） | 射线扫描 → 发布 `/scan`（frame `laser`） |

验证与手动驾驶：

```bash
rostopic list                     # 应能看到 /scan /odom /cmd_vel
rostopic hz /scan                 # 约 5.5 Hz
rostopic echo /odom -n1
rosrun teleop_twist_keyboard teleop_twist_keyboard.py   # 键盘 i/j/l/, 控制，q 退出
```

### 2.6 `worlds/`

| 路径 | 说明 |
|------|------|
| `worlds/hello.world` | 场地：地面 + 阳光；障碍物 `unit_box`(-1.16, 2.57)、`unit_cylinder`(-3.68, -3.43)、`unit_cylinder_0`(5.16, 2.63)、`unit_sphere`(3.09, -3.65)；以及房间模型 `Untitled` |
| `worlds/Untitled/` | 上面那个房间模型的源文件：`model.config` + `model.sdf`，内含 `Door_0`、`Stairs_0`、`Wall_2/5/6/7/8` |

> 换场景就改 `demo03_laser.launch` 里的 `world_name`，或另存一个 world 文件。

---

## 3. `nav_demo` 详解

### 3.1 包信息

- 依赖：`amcl`、`gmapping`、`map_server`、`move_base`
- 无源码节点，纯 launch + 参数 + 地图

### 3.2 `launch/` 逐个说明

| launch 文件 | 功能 | 启动的节点 | 是否含 `use_sim_time` |
|-------------|------|-----------|----------------------|
| `nav_slam.launch` | **建图（SLAM）** | `slam_gmapping` + `joint_state_publisher` + `robot_state_publisher` + `rviz` | ✅ `true` |
| `nav02_map_save.launch` | **保存地图** | `map_saver` | ❌ |
| `nav03_map_server.launch` | **只加载地图** | `map_server`（`arg map` 默认 `nav.yaml`） | ❌ |
| `nav04_amcl.launch` | **只做定位（AMCL）** | `amcl` | ❌ |
| `move_base.launch` | **只做路径规划** | `move_base`（加载 5 个 yaml） | ❌ |
| `test_amcl.launch` | 定位调试 | `rviz` + JSP + RSP + `nav03` + `nav04`（**无 move_base**） | ❌ |
| `move_test.launch` | ★ **已知地图的完整导航** | `map_server`(nav.yaml) + `nav04_amcl` + `move_base` + `rviz` + JSP + RSP | ❌ |
| `nav05_self.launch` | 边建图边规划（实验） | `nav_slam` + `move_base` | ✅（来自 nav_slam） |

各节点功能：

- **`slam_gmapping`**（`nav_slam.launch`）：订阅 `/scan` + TF，用粒子滤波在线建图，发布 `/map`（`nav_msgs/OccupancyGrid`）并发布 TF `map→odom`。关键参数：`base_frame=base_footprint`、`odom_frame=odom`、`map_frame=map`、`particles=30`、`map_update_interval=5.0`、`maxUrange=16.0`、`delta=0.05`（分辨率 5 cm）、建图范围 ±50 m
- **`map_server`**（`nav03` / `nav02`）：读 `.yaml`+`.pgm` 发布 `/map`、`/map_metadata`；`map_saver` 反之把 `/map` 存成文件
- **`amcl`**（`nav04_amcl.launch`）：蒙特卡洛定位。`odom_model_type=diff`（差速）、`laser_model_type=likelihood_field`、粒子 500~5000；`odom_frame_id=odom`、`base_frame_id=base_footprint`、`global_frame_id=map`。发布 **`/amcl_pose`** 与 TF `map→odom`
- **`move_base`**（`move_base.launch`）：全局规划（默认 `navfn/NavfnROS`）+ 局部规划（`base_local_planner/TrajectoryPlannerROS`）+ 双层代价地图。发布全局路径 **`/move_base/NavfnROS/plan`**、局部路径 `/move_base/TrajectoryPlannerROS/local_plan`、以及 **`/cmd_vel`**；订阅 `/move_base_simple/goal`（rviz 的 “2D Nav Goal”）
- **`joint_state_publisher` / `robot_state_publisher`**：由 URDF 计算并发布静态/关节 TF（如 `base_link→camera`、`base_link→support→laser`）。⚠️ **依赖全局参数 `robot_description`，该参数由 `urdf02_gazebo` 的 launch 提供**（见 §4.1）

### 3.3 `param/` 参数文件

| 文件 | 关键内容 |
|------|---------|
| `costmap_common_params.yaml` | 全局/局部代价地图共用：`robot_radius: 0.12`（圆形车）、`obstacle_range: 3.0`、`raytrace_range: 3.5`、`observation_sources: scan`，`scan: {sensor_frame: laser, data_type: LaserScan, topic: scan, marking: true, clearing: true}` |
| `global_costmap_params.yaml` | `global_frame: map`、`robot_base_frame: base_footprint`、`static_map: true`、`inflation_radius: 0.2`、`cost_scaling_factor: 10.0`、更新/发布 1 Hz |
| `local_costmap_params.yaml` | `global_frame: odom`、`static_map: false`、`rolling_window: true`（3×3 m 滚动窗口）、`resolution: 0.05`、`inflation_radius: 0.5`、10 Hz |
| `base_local_planner_params.yaml` | `TrajectoryPlannerROS`：`max_vel_x: 0.5`、`min_vel_x: 0.1`、`max_vel_theta: 1.0`、`acc_lim_x: 1.0`、`acc_lim_theta: 0.6`、`xy_goal_tolerance: 0.10`、`yaw_goal_tolerance: 0.05`、`holonomic_robot: false`、`sim_time: 0.8` |

> `move_base.launch` 里 `costmap_common_params.yaml` 被**加载两次**，分别挂到 `global_costmap` 和 `local_costmap` 命名空间下，这是标准写法，不是笔误。

### 3.4 `map/` 地图

| 文件 | 说明 |
|------|------|
| `nav.yaml` + `nav.pgm` | 1984×1984 px @ 0.05 m/px = **99.2 m × 99.2 m**，`origin: [-50, -50, 0]` |
| `nav2.yaml` + `nav2.pgm` | 同上尺寸；**`pp_learning` 用的就是这张**（仿真里重新建的地图） |
| `empty.yaml` + `empty.pgm` | ⚠️ **两个文件都是 0 字节的空文件**，不可用 |

> `nav.yaml` / `nav2.yaml` 里的 `image:` 是**绝对路径** `/root/catkin_ws/src/nav_demo/map/nav.pgm`，换机器/换目录必须改。

### 3.5 启动命令

```bash
# 只加载地图（可换地图文件）
roslaunch nav_demo nav03_map_server.launch map:=nav2.yaml      # arg 有默认值，可覆盖

# 只做定位调试
roslaunch nav_demo test_amcl.launch

# 保存地图
roslaunch nav_demo nav02_map_save.launch
```

---

## 4. 联合使用：完整实操流程

### 4.1 依赖关系与话题数据流

```
                    ┌─────────────────────── urdf02_gazebo ───────────────────────┐
                    │  demo03_laser.launch                                       │
                    │    ├─ 参数服务器: robot_description ◄──────┐(nav_demo 的 RSP 用)│
                    │    ├─ gzserver + gzclient (world: hello.world)             │
                    │    └─ spawn_model → mycar 出现在世界里                      │
                    │                                                            │
                    │  move.urdf.xacro:  /cmd_vel ──► 差速驱动 ──► 车轮转动        │
                    │                            └─► /odom + TF odom→base_footprint
                    │  laser.urdf.xacro: 射线扫描 ──► /scan (frame: laser)        │
                    └────────────────────────────────────────────────────────────┘
                                          │  /scan   /odom
                                          ▼
                    ┌──────────────────────── nav_demo ───────────────────────────┐
                    │  A) nav_slam.launch :  slam_gmapping ──► /map + TF map→odom │
                    │  B) nav04_amcl.launch: amcl        ──► /amcl_pose + TF map→odom
                    │  move_base.launch    : move_base   ──► /move_base/NavfnROS/plan
                    │                                     └─► /cmd_vel ──┐        │
                    └──────────────────────────────────────────────────┼────────┘
                                                                       ▼
                                                       回到 Gazebo 驱动小车（闭环）
```

**关键耦合点（容易踩坑）**：`nav_demo` 里的 `robot_state_publisher` 依赖全局参数
`robot_description`，而该参数**只在 `urdf02_gazebo` 的 launch 中设置**。
所以必须先启动 `urdf02_gazebo` 的 launch，再启动 `nav_demo` 的 launch；
单独启动后者会看到 `[ERROR] Could not find parameter robot_description on parameter server`（已实测）。

### 4.2 TF 坐标系树

```
map ──(gmapping 或 amcl 发布)──► odom ──(gazebo 差速插件发布)──► base_footprint
                                                                    │ (urdf 固定关节)
                                                                base_link
                                                                  ├── left_wheel / right_wheel   (continuous)
                                                                  ├── front_wheel / back_wheel   (continuous)
                                                                  ├── camera
                                                                  └── support ──► laser
```

查看方式：`rosrun tf2_tools view_frames.py` 生成 `frames.pdf`；或 rviz 里加 TF 显示。

### 4.3 流程 A：在 Gazebo 里建图（SLAM）

```bash
# 终端 0（每个终端都执行一次）
source ~/catkin_ws/devel/setup.bash

# 终端 1：启动仿真世界与带雷达的小车
roslaunch urdf02_gazebo demo03_laser.launch

# 终端 2：启动 gmapping 建图（自带 rviz，并设置 use_sim_time=true）
roslaunch nav_demo nav_slam.launch

# 终端 3：键盘开着车把场地逛一圈（rviz 里的地图会逐渐长出来）
rosrun teleop_twist_keyboard teleop_twist_keyboard.py

# 终端 4：逛完保存地图（默认存到 nav_demo/map/nav2）
roslaunch nav_demo nav02_map_save.launch
```

rviz 配置要点（终端 2 的 rviz 里）：
- `Fixed Frame` 设为 `map`
- 添加 `LaserScan`（Topic `/scan`）、`Map`（Topic `/map`）、`TF`、`RobotModel`

保存地图说明：
- `nav02_map_save.launch` 里 `filename` 被**写死**成 `$(find nav_demo)/map/nav2`，
  写成 `<arg name="filename" value="..."/>`（常量），**不能用 `filename:=xxx` 从命令行覆盖**（已实测会报
  `Invalid <arg> tag: cannot override arg 'filename'`）。要改路径请编辑该 launch 文件，或直接用：
  ```bash
  rosrun map_server map_saver -f /tmp/mymap      # 自定义路径，生成 mymap.pgm + mymap.yaml
  ```
- 用 `map_saver` 存出来的 yaml 里 `image:` 是当前绝对路径，必要时手工改成相对/正确路径。

### 4.4 流程 B：已有地图上的自主导航

```bash
# 终端 1：仿真
roslaunch urdf02_gazebo demo03_laser.launch

# 终端 2：先打开仿真时间，再启动导航栈
rosparam set use_sim_time true
roslaunch nav_demo move_test.launch map:=nav2.yaml
```

> ⚠️ `move_test.launch` / `nav04_amcl.launch` / `move_base.launch` 里**没有** `use_sim_time` 参数。
> 与 Gazebo 联用时必须先 `rosparam set use_sim_time true`（在终端 1 已启动 master 之后执行），
> 否则各节点用墙上时钟、TF 时间戳与 `/clock` 对不上，会出现 TF 超时、AMCL 不收敛。

在 rviz 里的操作顺序：

1. `Fixed Frame` 设为 `map`
2. 加 `Map`(`/map`)、`LaserScan`(`/scan`)、`Path`(`/move_base/NavfnROS/plan`)、`Pose`(`/amcl_pose`)
3. 工具栏 **"2D Pose Estimate"** 在图上点一下并拖出朝向 → 给 AMCL 一个初始位姿（否则粒子撒在整张图上，收敛很慢）
4. 工具栏 **"2D Nav Goal"** 点目标点 → move_base 规划并驱车前往，rviz 中可见绿色全局路径

辅助排查：

```bash
rostopic echo /amcl_pose -n1          # 定位是否正常
rostopic echo /move_base/NavfnROS/plan -n1
rostopic hz /cmd_vel                  # 是否有速度指令下发
rosrun rqt_reconfigure rqt_reconfigure # 在线调代价地图/规划器参数
```

### 4.5 流程 C：纯追踪（Pure Pursuit）—— 一条命令全栈

`pp_learning/self_move_base.launch` 复用了 `nav_demo` 的地图、AMCL 与 move_base 参数，
但把 move_base 的 `/cmd_vel` 重映射到 `dummy_cmd_vel`（只做规划），真正的速度由 `test815` 节点发布：

```bash
roslaunch urdf02_gazebo demo03_laser.launch
roslaunch pp_learning self_move_base.launch          # map_server(nav2.yaml) + amcl + move_base + test815 + rviz
```

数据流：`/amcl_pose` + `/move_base/NavfnROS/plan` + `/scan` → `test815` → `/cmd_vel`。

---

## 5. 已知问题与注意事项

1. **`urdf02_gazebo/demo01_helloworld.launch` 包名拼写错误**
   文件中写的是 `$(find urfd02_gazebo)`（`urdf` 误写成 `urfd`）。实测启动直接报
   `Resource not found: urfd02_gazebo`。正确包名是 **`urdf02_gazebo`**，把这一行改掉即可。
   （`devel/share/urfd02_gazebo/` 与 `build/urfd02_gazebo/` 是历史残留，`rospack find urfd02_gazebo` 找不到它，别被误导。）

2. **`demo02_car.launch` / `my_car.launch` 没有激光雷达**
   两者加载的是 `demo05.urdf.xacro`，只含雷达的**外壳几何**，没有 `<sensor>`，因此**没有 `/scan`**。
   建图/导航必须用 **`demo03_laser.launch`**（加载 `demo06_laser.urdf.xacro`，含 `laser.urdf.xacro` 的真实雷达）。
   两个 launch 内容实质相同（仅注释与空白差异），属重复文件。

3. **`nav_demo` 的 launch 无法独立启动**
   `nav_slam.launch` / `test_amcl.launch` / `move_test.launch` 都启动 `robot_state_publisher`，
   而该节点需要全局参数 `robot_description`。实测缺少时报
   `[ERROR] Could not find parameter robot_description on parameter server`。
   必须先启动 `urdf02_gazebo` 的 launch（由它设置该参数）。

4. **`use_sim_time` 缺失**
   只有 `nav_slam.launch` 设置了 `use_sim_time=true`。`move_test.launch`、`test_amcl.launch`、
   `nav04_amcl.launch`、`move_base.launch` 都没有。与 Gazebo 联用前需手动
   `rosparam set use_sim_time true`，否则 TF 时间戳与仿真时间不一致。

5. **`nav02_map_save.launch` 的保存路径不可通过命令行覆盖**
   `filename` 是常量 `<arg ... value=...>`，`filename:=/path` 会报
   `Invalid <arg> tag: cannot override arg 'filename', which has already been set`（已实测）。
   改路径请编辑 launch，或直接用 `rosrun map_server map_saver -f <路径>`。

6. **地图 YAML 中是绝对路径**
   `map/nav.yaml`、`map/nav2.yaml` 的 `image:` 指向 `/root/catkin_ws/src/nav_demo/map/*.pgm`。
   迁移到别的机器/目录时必须修改，否则 `map_server` 找不到图片。

7. **`map/empty.pgm` 与 `map/empty.yaml` 是 0 字节空文件**，不要引用它们作为地图。

8. **`urdf02_gazebo/launch/rviz.launch` 单独用看不到模型**
   它只启动 `rviz` + `joint_state_publisher` + `robot_state_publisher`，没有加载 `robot_description`，
   RSP 会因缺参数报错。若只想在 rviz 里看模型，应先让 `robot_description` 存在于参数服务器
   （例如启动过 `demo03_laser.launch`），或自行在 launch 中补上 `<param name="robot_description" .../>`。

9. **`udf01/demo04_control.launch` 依赖未声明的 `arbotix_python`**
   该 launch 使用 `<node pkg="arbotix_python" type="arbotix_driver" .../>`，但包内 `package.xml`
   未声明该依赖；需 `sudo apt install ros-noetic-arbotix`（本机 `~/catkin_ws/arbotix_ros` 下也有源码）。
   （`udf01` 非本文重点，仅作提醒。）

10. **`pp_learning/src/nav_pure_pursuit.cpp` 计算了控制量但没有发布**
    实测该文件只在构造函数中 `advertise("/cmd_vel")`，全文没有任何 `.publish(...)` 调用；
    **可用版本是 `test815.cpp`**（其中有 `cmd_pub_.publish(cmd)`），`self_move_base.launch` 启动的也正是 `test815`。

11. **重复 TF 的可能告警**
    `move.urdf.xacro` 同时开启了 `publishWheelTF` 与 `publishWheelJointState`，而
    `nav_slam.launch` 又启动了 `joint_state_publisher` + `robot_state_publisher`，
    车轮的 TF 会被发布两次（终端可能出现 `TF_REPEATED_DATA` 告警）。
    如需消除，可二选一：把差速插件的 `publishWheelTF` 设为 `false`，或不再启动 `joint_state_publisher`。

12. **摄像头默认关闭**
    `demo06_laser.urdf.xacro` 中 `my_sensors_camara.urdf.xacro` 被注释掉了，
    所以默认**没有** `/camera/image_raw`。需要相机图像时取消该行注释。

---

## 6. 命令速查表

```bash
# ---- 环境 ----
cd ~/catkin_ws && catkin_make && source devel/setup.bash

# ---- urdf02_gazebo（仿真）----
roslaunch urdf02_gazebo demo03_laser.launch            # ★ 带雷达的车 + hello.world 场景
roslaunch urdf02_gazebo demo03_laser.launch gui:=false # 无 GUI
roslaunch urdf02_gazebo demo02_car.launch              # 仅看模型/开车（无 /scan）
roslaunch urdf02_gazebo rviz.launch                    # 仅 rviz + JSP + RSP
rosrun teleop_twist_keyboard teleop_twist_keyboard.py  # 键盘遥控

# ---- nav_demo（导航）----
roslaunch nav_demo nav_slam.launch                     # 建图（gmapping + rviz）
roslaunch nav_demo nav02_map_save.launch               # 保存地图 → map/nav2.*
roslaunch nav_demo nav03_map_server.launch map:=nav2.yaml   # 只加载地图
roslaunch nav_demo test_amcl.launch                    # 只做定位调试
rosparam set use_sim_time true                         # 与 Gazebo 联用前必做
roslaunch nav_demo move_test.launch map:=nav2.yaml     # ★ 已知地图完整导航

# ---- pp_learning（纯追踪，一条命令全栈）----
roslaunch pp_learning self_move_base.launch

# ---- 常用排查 ----
rostopic list && rostopic hz /scan && rostopic hz /odom
rostopic echo /amcl_pose -n1
rosrun tf2_tools view_frames.py                        # 生成 frames.pdf 看 TF 树
rosrun rviz rviz                                       # 手动开 rviz
rosrun rqt_reconfigure rqt_reconfigure                  # 在线调参
```

## 7. 典型三条工作流（记忆卡片）

```
① 建图   demo03_laser.launch  →  nav_slam.launch  →  键盘遥控逛场地  →  nav02_map_save.launch
② 导航   demo03_laser.launch  →  rosparam set use_sim_time true  →  move_test.launch map:=nav2.yaml
                                                                    →  rviz: 2D Pose Estimate + 2D Nav Goal
③ 纯追踪 demo03_laser.launch  →  pp_learning/self_move_base.launch
```
