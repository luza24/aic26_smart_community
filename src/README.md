# AIC26 智慧社区仿真工作空间

> 工作空间：`/root/catkin_ws_aic` · ROS 1 Noetic · Gazebo 11.15.1 · Ubuntu 20.04（WSL2 / Docker）
> 本文分析 `src/` 的架构现状：**哪些能跑、哪些是骨架、哪些坑必须绕**。

本文的事实来自对仓库的实际检查（`rospack`、`diff`、读文件）以及**实机启动验证**：§4.2 标注「已实测」的
两条结论，是用 `gzserver` 真起了一遍场景、再用 `/gazebo/get_world_properties`、`rosservice list`、
`rostopic` 查出来的。仍属推测的地方会明确标注 **「未实测」**。
历史导航栈（`nav_demo` / `urdf02_gazebo`）的逐文件说明见 [src/PROJECT_OVERVIEW.md](src/PROJECT_OVERVIEW.md)，本文不重复。

---

## 1. 一句话架构

工作空间里有 **三条互不相干的线**，别把它们当成一套系统：

| 线 | 包 | 状态 | 用途 |
|----|----|------|------|
| **AIC26 主栈** | `aic26_*`（10 个） | 仅 description / gazebo / slam 有实现，其余 7 个是空骨架 | 新比赛栈，目标是智慧社区场景 |
| **教学/历史导航** | `nav_demo`、`urdf02_gazebo` | 完整可用 | 建图、AMCL 定位、move_base 导航闭环 |
| **仿真资产与插件** | `roscar-gazebo-models`、`gazebo_ros_model_color`、`visual_plug` | 完整可用（前两个是 git 仓库） | 场景模型库、红绿灯改色插件、红绿灯自动循环插件 |

`aic26_*` 目前**复用不了** `nav_demo` 的导航栈：新栈自己还没有 navigation / bringup 的实现，
而 `aic26_gazebo` 起出来的世界没有 `robot_description`，`nav_demo` 的 launch 又强依赖这个参数。
两条线现在是拼接关系，不是继承关系。

---

## 2. src 目录结构

```
src/
├── aic26_*                    # ★ AIC26 竞赛主栈（分层，多数为空骨架）
│   ├── aic26_bringup          #   总启动入口        —— 空骨架
│   ├── aic26_description      #   机器人 URDF/xacro  —— ★ 已实现
│   ├── aic26_gazebo           #   世界 + 模型库      —— ★ 已实现
│   ├── aic26_msgs             #   自定义消息         —— 空骨架（无 .msg/.srv）
│   ├── aic26_perception       #   视觉感知           —— 空骨架
│   ├── aic26_ocr              #   文字识别           —— 空骨架
│   ├── aic26_decision         #   决策/任务调度      —— 空骨架
│   ├── aic26_navigation       #   导航封装           —— 空骨架
│   ├── aic26_slam             #   建图               —— ★ 已实现（1 个 launch）
│   └── aic26_utils            #   公共工具           —— 空骨架
│
├── nav_demo/                  # 历史导航栈：gmapping / map_server / amcl / move_base
├── urdf02_gazebo/             # 历史仿真：demo06 两轮差速小车 + 场地
├── visual_plug/               # 红绿灯 WorldPlugin（transport 循环切灯）+ 场地 world
├── demo_plugin/               # 空包（只有 CMakeLists.txt + package.xml）
├── gazebo_ros_model_color/    # ★ git 仓库：verlab 的 visual 插件，按 ROS 服务改模型颜色
├── roscar-gazebo-models/      # ★ git 仓库：比赛模型库（NHK-DOT），上游资产
├── CMakeLists.txt -> /opt/ros/noetic/share/catkin/cmake/toplevel.cmake
└── PROJECT_OVERVIEW.md        # 历史导航栈的详细文档
```

`build/`、`devel/` 里混有大量**旧工作区残留**（`diffbot*`、`pp_learning`、`rplidar_ros` 等），
`src/` 中已无对应源码，忽略即可。

---

## 3. aic26_* 分层职责与实现状态

| 包 | 预期职责 | 依赖（package.xml） | 实现状态 |
|----|---------|--------------------|---------|
| `aic26_description` | 机器人模型 | `urdf` `xacro` `robot_state_publisher` | ✅ `urdf/` 7 个 xacro |
| `aic26_gazebo` | 世界、模型、启动 | `gazebo_ros` `gazebo_plugins` | ✅ `models/` 8 个、`worlds/` 2 个、`launch/` 2 个 |
| `aic26_slam` | 建图 | `gmapping` `map_server` | ⚠️ 仅 `launch/gmapping.launch`，无保存/加载地图 |
| `aic26_navigation` | 导航 | `move_base` `costmap_2d` | ❌ `config/` `launch/` 皆空 |
| `aic26_perception` | 视觉感知 | `cv_bridge` `image_transport` `sensor_msgs` | ❌ `config/` `launch/` `src/` `scripts/` 皆空 |
| `aic26_ocr` | 文字识别 | 同上 | ❌ 同上 |
| `aic26_decision` | 决策 | `actionlib` `aic26_msgs` `move_base_msgs` | ❌ `config/` `launch/` `src/` `scripts/` 皆空 |
| `aic26_msgs` | 自定义消息 | `message_generation` `std_msgs` | ❌ `msg/` `srv/` 为空，CMakeLists 里也无 `add_message_files` |
| `aic26_utils` | 公共工具 | `roscpp` `rospy` `geometry_msgs` | ❌ `include/` `src/` `scripts/` 皆空 |
| `aic26_bringup` | 总入口 | 仅 `catkin` | ❌ `launch/` 为空 |

> 这 7 个骨架包已能正常 `catkin_make`（`catkin_package()` 为空、无 `install()` 规则），
> 目录结构和依赖声明是齐的，往里填代码即可，不用重新建包。

---

## 4. 已实现部分详解

### 4.1 `aic26_description` —— 机器人模型 `armbot`

`urdf/` 下 7 个 xacro，**总装文件是 `gazebo_car_union.xacro`**（robot name = `armbot`）：

```
gazebo_car_union.xacro          ← 总装：包含以下 5 个 + 底盘驱动插件
├── gazebo_head.xacro           # 纯宏：球/圆柱/长方体惯量矩阵（无 link）
├── gazebo_car.xacro            # 4 轮底盘 + 轮子宏
├── gazebo_laser.xacro          # 支撑杆 support + 雷达 laser（含真实 ray 传感器）
├── gazebo_camera.xacro         # 摄像头 camera（只有几何）
├── gazebo_sensors.xacro        # camera 的 <sensor> + libgazebo_ros_camera.so
└── move.urdf.xacro             # ⚠️ 僵死文件，见下
```

**底盘与驱动**（`gazebo_car.xacro` + 总装的插件段）：

| 项 | 值 |
|----|-----|
| 底盘 | box `0.30 × 0.20 × 0.08`，质量 0.50 kg |
| 轮子 | 圆柱 r=0.08、厚 0.04，质量 0.10 kg，4 个（front/back × left/right） |
| 轮位 | `wheel_x = 0.30×0.30 = 0.09`，`wheel_y = (0.10+0.02)×1.10 = 0.132` |
| 驱动插件 | `libgazebo_ros_skid_steer_drive.so`（**滑移转向**，四轮联动） |
| 轮距 / 轮径 | `${wheel_y*2}` = **0.264** / `${wheel_radius*2}` = **0.16** |
| 接口 | 订阅 `/cmd_vel`，发布 `/odom`，广播 TF `odom→base_footprint` |
| 力矩 | `torque = 20` |

**传感器**：

| 传感器 | 话题 | frame | 参数 |
|--------|------|-------|------|
| 激光 `laser_sensor` | `/scan` | `laser` | 720 线，±135°，0.10~12.0 m，40 Hz，高斯噪声 σ=0.01 |
| 相机 `camera_node` | `camera/image_raw` | `camera` | 1280×720，水平 FOV 1.396 rad，30 Hz |

**TF 树**（URDF 链路，高度与存盘 world 里的固定关节数值逐一吻合）：

```
odom ──(skid_steer 插件)──► base_footprint ──0.08──► base_link ──0.10──► support ──0.085──► laser
                                                          ├── front_left_wheel  (continuous, 轴 0 1 0)
                                                          ├── front_right_wheel (continuous)
                                                          ├── back_left_wheel   (continuous)
                                                          ├── back_right_wheel  (continuous)
                                                          └── camera             (camera_z = 0.04+0.0125+0.2 = 0.2525)
```

`base_footprint → laser` 合计 **0.265 m**，与 `aic26_slam/launch/gmapping.launch` 里写死的静态发布者数值一致。

> ⚠️ **`move.urdf.xacro` 是僵死文件**：它是从 `urdf02_gazebo` 抄来的两轮差速插件配置，
> 引用 `left_wheel2base_link` / `right_wheel2base_link` 两个**本模型里不存在**的关节，
> 而且没有任何文件 `include` 它（总装用的是 skid_steer）。可以安全删除，别被它误导。
>
> ⚠️ 目前**没有任何 launch 引用 `aic26_description`**：`gazebo_car_union.xacro` 不会被
> 自动展开成 `robot_description`。它唯一的“落地”方式是已经存进
> `aic26_gazebo/worlds/gazebo_test.world` 的那份内联 armbot（实测该 world 能起出 `armbot` 模型）。

### 4.2 `aic26_gazebo` —— 世界与模型库

**`worlds/`**

| 文件 | 内容 | 前置条件 |
|------|------|---------|
| `gazebo_test.world` | 11×8 m 展台地面 + 4.3×4.3 围墙 + 4.2×4.2 贴图地面 + **armbot** + 3 个 cp 车/车牌板 + ro1/ro2 人物板 + 2 组红绿灯 | 只要 source 本工作空间 |
| `model_gallery.world` | 模型展厅：每种模型各放一件，**也含可驾驶的小车** `competition_car` | 还需 source `roscar-gazebo-models/setup.bash` |

两个 world 都是**存盘场景**：模型定义（含 `<state>` 初始位姿）直接内联在 world 里，
**机器人已经站在场上**，launch 不需要 spawn，也不设 `robot_description`。

**✅ 已实测（`gzserver` 直起 + 查服务/话题）**

`gazebo_test.launch` 起出来的 11 个模型：

```
gallery_floor  map_walls  map_plane  ro1  ro2  cp  cp_clone  cp_clone_0
traffic_light  traffic_light_0  armbot
```

话题齐全，且频率与配置一致：

| 话题 | 实测 |
|------|------|
| `/scan` | **40.0 Hz**（配置 40） |
| `/odom` | **100.0 Hz**（配置 updateRate 100） |
| `/tf` | `odom → base_footprint` |
| 其它 | `/cmd_vel`、`/camera/image_raw`、`/camera/camera_info`、`/clock`、`/gazebo/*` |

`model_gallery.launch` **先 `source src/roscar-gazebo-models/setup.bash` 后**，12 个模型全部加载成功：

```
gallery_floor  terrain_original_map_plane  competition_map_walls  terrain_route_ground
competition_person_board_1  competition_person_board_2  competition_car_plate_board
competition_horizontal_traffic_light
competition_red_lens  competition_yellow_lens  competition_green_lens
competition_car          ← 带 skid_steer 插件，可驾驶
```

**`launch/`**

```bash
roslaunch aic26_gazebo gazebo_test.launch      # 比赛场景（含机器人，可直接开车）
roslaunch aic26_gazebo model_gallery.launch    # 模型展厅（需先 source roscar setup.bash）
```

两者都经 `empty_world.launch` 设 `/use_sim_time = true`。

**`models/`**：`cp`(车/车牌板)、`ro1` `ro2`(人物立牌)、`map_plane`(贴图地面)、`map_walls`(围墙)、
`my_ground_plane`(路线地面)、`traffic_light`(红绿灯)、`test_car`。

模型路径靠 `package.xml` 的导出生效：

```xml
<export><gazebo_ros gazebo_model_path="${prefix}/models"/></export>
```

这条**只在包位于 `ROS_PACKAGE_PATH` 上时才有用**：`libgazebo_ros_paths_plugin.so` 被
`gazebo_ros/gzserver` 包装脚本作为 system plugin 加载，由它在 gzserver 进程内读取
`gazebo_model_path` 导出标签并注册给 Gazebo。所以启动前必须 source 本工作空间。

### 4.3 `aic26_slam` —— 建图

`launch/gmapping.launch` 做了两件事：

1. **补一个静态 TF** `base_footprint → laser`（`0 0 0.265`）——因为新栈里没有 `robot_state_publisher`，
   没有它 gmapping 拿不到雷达坐标系（launch 里注释写的是「强制添加静态发布者」，就是这个原因）。
2. 起 `slam_gmapping`：`base_frame=base_footprint`、`odom_frame=odom`、`map_frame=map`、
   `scan_topic=/scan`、`particles=80`、`delta=0.05`、地图范围 ±6 m、`linear/angularUpdate=0.10`。
   另外起一个 `rviz`。

> - 该 launch **没有设 `use_sim_time`**。配合 `gazebo_test.launch` 时由后者设置，没问题；
>   单独用要自己 `rosparam set use_sim_time true`。
> - `aic26_slam` **没有保存/加载地图的 launch**。保存地图目前只能：
>   `rosrun map_server map_saver -f <路径>`，或沿用 `nav_demo` 的 `nav02_map_save.launch`。

### 4.4 仿真资产的来源：上游 vs 改写版

`aic26_gazebo/models/` 和 `aic26_description/urdf/` **都是从 `roscar-gazebo-models` 拷来的改写版**，
不是上游原样：

| 对比 | 结果 |
|------|------|
| `aic26_description/urdf/*.xacro` ↔ `roscar-.../robot/xacro/*.xacro` | 7 个文件里 6 个**仅换行符差异**（CRLF→LF），仅 `gazebo_laser.xacro` 有实质改动：`<always_on>true</always_on>`、`<visualize>true</visualize>`，并删掉了「设为 false 可隐藏激光束」的注释 |
| `aic26_gazebo/models/*` ↔ `roscar-.../competition_models/*` | 同名同源但**内容普遍不同**（`model.sdf`、`.material`、`model.config` 都有差异） |

改写的核心是**红绿灯**——两套完全不同的实现：

| | 上游（roscar + `visual_plug`） | AIC26 改写版 |
|--|------------------------------|-------------|
| 结构 | 1 个主体（3 个 `*_lens_off` 暗灯片）+ **3 个独立发光灯片 model** | 单模型内 3 个灯片 visual |
| 机制 | `libtraffic_light_plugin.so`（**WorldPlugin**，gazebo transport 发 `~/visual` 消息） | `libgazebo_ros_model_color.so`（**visual 插件**，ROS 服务） |
| 控制 | 自动循环 红 10s → 绿 15s → 黄 5s，参数 `<red>/<green>/<yellow>/<group>` | 手动调服务 `/<ns>/{red,yellow,green}_lens_color`（`gazebo_msgs/SetLightProperties`） |
| 谁在用 | `model_gallery.world`、`visual_plug/worlds/robot_nav_field.world` | `gazebo_test.world` |

两条线各自的资产是自洽的：展厅引用的 `model://traffic_light_{red,yellow,green}_lens`
**只存在于上游**（`~/.gazebo/models/` 与 `roscar-.../competition_models/`），
所以展厅那条线对应的是 `visual_plug` 的自动循环设计。

> ⚠️ **改色插件是 visual 插件**（`GZ_REGISTER_VISUAL_PLUGIN`），依赖渲染端。
> 实测：在 `gzserver` 里**没有** `*_lens_color` 服务——与「改色应在 gzclient 侧生效」的预期一致。
> `gui:=false` 时改色服务是否可用**未实测**。
>
> ⚠️ `model://traffic_light` 这个**主体模型**在 `~/.gazebo/models/`（上游版）和
> `aic26_gazebo/models/`（改写版）里同名。`model_gallery.world` 引用它时命中哪一份
> **未实测**（取决于 Gazebo 的模型路径优先级）。两者外观差异是灯片状态：上游为 `*_lens_off`（暗），
> 改写版是已点亮的灯片。若展厅里红绿灯表现不对，先检查/清理 `~/.gazebo/models/traffic_light*`。

---

## 5. 历史与示例包

| 包 | 说明 |
|----|------|
| `nav_demo` | `gmapping` / `map_server` / `amcl` / `move_base` 全套。`move_test_aic.launch` 是为本工作区新加的「已知地图导航」入口（`nav2.yaml` + amcl + move_base + rviz + JSP/RSP）。细节见 [PROJECT_OVERVIEW.md](src/PROJECT_OVERVIEW.md) |
| `urdf02_gazebo` | 两轮差速小车（`mycar`）+ 场地。`aic_car.launch` 与 `demo03_laser.launch` 都加载 `visual_plug/worlds/robot_nav_field.world`；**`demo03_laser.launch` 是带 `/scan` 的那条** |
| `visual_plug` | 上面那张场地的提供者 + 红绿灯自动循环 WorldPlugin（`src/traffic_light_plugin.cc`，部署约定是「1 主体 + 3 独立灯片」） |
| `demo_plugin` | 空包，无源码 |
| `gazebo_ros_model_color` | git 仓库（`github.com/verlab/gazebo_ros_model_color`，GPL-3.0）。visual 插件，把 `gazebo_msgs/SetLightProperties` 服务转成对 visual 的 `SetAmbient/SetDiffuse`。**aic26 红绿灯依赖它**，已编译出 `devel/lib/libgazebo_ros_model_color.so` |
| `roscar-gazebo-models` | git 仓库（`github.com/NHK-DOT/roscar-gazebo-models`）。模型库 + `setup.bash` + `install_models.sh` + 展厅 launch。**无 `package.xml`**，所以不参与 `catkin_make`，只能通过 `setup.bash` 或 `GAZEBO_MODEL_PATH` 使用 |

`start.launch`（工作区根目录）串起了历史那条线：

```xml
<include file="$(find urdf02_gazebo)/launch/demo03_laser.launch" />
<include file="$(find nav_demo)/launch/move_test_aic.launch" />
```

---

## 6. 怎么跑

### 6.1 环境准备（**先看 §7.1，这里有个必须知道的覆盖陷阱**）

```bash
cd ~/catkin_ws_aic
catkin_make                 # aic26_* 多为资源包，改 launch/xacro/world 后无需重编
source devel/setup.bash
```

### 6.2 比赛场景 / 展厅

```bash
roslaunch aic26_gazebo gazebo_test.launch      # ✅ 已实测：11 个模型 + /scan + /odom + /cmd_vel
rosrun teleop_twist_keyboard teleop_twist_keyboard.py     # 键盘驾驶

# 展厅（可驾驶的小车 + 全部模型展示）——需要额外挂上 roscar 的模型路径
source src/roscar-gazebo-models/setup.bash
roslaunch aic26_gazebo model_gallery.launch    # ✅ 已实测：12 个模型全部加载
```

### 6.3 在比赛场景里建图

```bash
# 终端 1
roslaunch aic26_gazebo gazebo_test.launch
# 终端 2（rviz 会一起起来，Fixed Frame 设 map）
roslaunch aic26_slam gmapping.launch
# 终端 3：开车逛一圈，然后把 /map 存下来
rosrun teleop_twist_keyboard teleop_twist_keyboard.py
rosrun map_server map_saver -f /tmp/aic26_map
```

### 6.4 历史导航闭环（目前唯一能跑通「导航到目标点」的路径）

```bash
roslaunch start.launch                                  # 从工作区根目录
# 等价于：
roslaunch urdf02_gazebo demo03_laser.launch
roslaunch nav_demo move_test_aic.launch
```

在 rviz 里：`Fixed Frame = map` → **2D Pose Estimate** 给初始位姿 → **2D Nav Goal** 下发目标。
注意 §7.4 的地图绝对路径问题。

---

## 7. 已知问题与坑

### 7.1 ⚠️⚠️ 双工作区覆盖：新工作区改的东西可能根本没生效

这是本环境**最容易踩的坑**，会静默地把你的修改变成无效操作：

```bash
# 默认 shell 里（/root/.bashrc 第 105 行）
$ echo $ROS_PACKAGE_PATH
/root/catkin_ws/src:/opt/ros/noetic/share        # ← 指向【旧】工作区
$ echo $GAZEBO_PLUGIN_PATH
/root/catkin_ws/devel/lib                        # ← 也是旧工作区
```

`/root/.bashrc` 会自动 `source /root/catkin_ws/devel/setup.bash`，而 `/root/catkin_ws_aic` 只在
**手动 source 之后**才进入路径尾部。后果：

```
$ rospack find nav_demo          → /root/catkin_ws/src/nav_demo       ← 旧工作区！
$ rospack find urdf02_gazebo     → /root/catkin_ws/src/urdf02_gazebo  ← 旧工作区！
$ rospack find visual_plug       → /root/catkin_ws/src/visual_plug    ← 旧工作区！
$ rospack find aic26_description → /root/catkin_ws_aic/src/...        ← 正常（旧工作区没有）
```

**当前危害有限**：已核对过，`nav_demo`、`urdf02_gazebo`、`visual_plug` 这两份副本目前**逐字节完全一致**
（`diff -rq` 无输出），所以跑起来行为一样。但只要你在 `catkin_ws_aic/src/nav_demo/` 下改文件，
**改动不会生效**——`$(find nav_demo)` 拿到的还是旧工作区那份，而且不会有任何报错。

**处理方式（任选）**：

```bash
# 方案一：只认新工作区（推荐 —— 让新工作区排在前面）
export ROS_PACKAGE_PATH=/root/catkin_ws_aic/src:$ROS_PACKAGE_PATH

# 方案二：改 /root/.bashrc，把自动 source 的那行指向新工作区
#   [ -f /root/catkin_ws_aic/devel/setup.bash ] && source /root/catkin_ws_aic/devel/setup.bash
#   export GAZEBO_PLUGIN_PATH=$HOME/catkin_ws_aic/devel/lib:$GAZEBO_PLUGIN_PATH
```

顺带一提，`GAZEBO_PLUGIN_PATH` 只指向旧工作区的 `devel/lib`，而旧工作区的 `lib/` 里**没有**
`libgazebo_ros_model_color.so`（只有 `libtraffic_light_plugin.so`）——aic26 红绿灯需要那个插件：

```
/root/catkin_ws/devel/lib/       libtraffic_light_plugin.so          (无 model_color)
/root/catkin_ws_aic/devel/lib/   libtraffic_light_plugin.so  libgazebo_ros_model_color.so
```

### 7.2 新栈与历史栈的参数耦合

`nav_demo` 的 `nav_slam.launch` / `test_amcl.launch` / `move_test_aic.launch` 都启动
`robot_state_publisher`，它需要全局参数 `robot_description`，而该参数**只由 `urdf02_gazebo` 的 launch 设置**。
所以**必须先起仿真、再起导航**，单独起后者会报
`Could not find parameter robot_description on parameter server`。

`aic26_gazebo` 的两个 launch **都不设这个参数**，所以 AIC26 世界目前接不上 `nav_demo` 的导航栈 ——
这也是 `aic26_navigation` / `aic26_bringup` 需要填的第一件事。

### 7.3 `use_sim_time` 不统一

只有 `empty_world.launch`（`aic26_gazebo` 两个 launch、`urdf02_gazebo` 的 launch 都经由它）和
`nav_demo/nav_slam.launch` 会设 `use_sim_time`。`nav04_amcl.launch` / `move_base.launch` /
`move_test_aic.launch` 都没有 —— 但经由 `demo03_laser.launch` 间接设置，所以 `start.launch` 这条链路是好的。
单独用 `nav_demo` 的导航 launch 时仍要手动 `rosparam set use_sim_time true`。

### 7.4 `nav_demo` 的地图是**旧工作区的绝对路径**

```yaml
# nav_demo/map/nav.yaml
image: /root/catkin_ws/src/nav_demo/map/nav.pgm        # ← 注意没有 _aic
# nav_demo/map/nav2.yaml
image: /root/catkin_ws/src/nav_demo/map/nav2.pgm
```

`/root/catkin_ws` 目前**仍然存在**，所以还能跑；一旦清理掉旧工作区，`map_server` 会找不到图片。
另外 `nav_demo/map/empty.pgm` 与 `empty.yaml` 都是 **0 字节空文件**，不要引用。

### 7.5 其它

1. **`model_gallery.launch` 必须先 `source src/roscar-gazebo-models/setup.bash`**：
   展厅引用的 `competition_car` 只存在于 `roscar-gazebo-models/robot/`，
   三个灯片模型只存在于 `~/.gazebo/models/` 与 `roscar-.../competition_models/`，
   都不在 `aic26_gazebo/models/` 里。补上路径后已实测可全部加载。
2. **`move.urdf.xacro` 引用了不存在的关节**，是僵死文件，无人 include。见 §4.1。
3. **`aic26_msgs` 没有任何消息定义**：`msg/` `srv/` 为空，CMakeLists 里也没有
   `add_message_files` / `generate_messages`。而 `aic26_decision` 已经声明依赖 `aic26_msgs` ——
   填消息时记得同时补 CMakeLists。
4. **aic26 包都没有 `install()` 规则**、`catkin_package()` 为空。devel 空间下 `$(find ...)`
   解析到源码目录，所以现在没问题；但 `catkin_make install` / 打包会缺资源文件。
5. **`docker/Dockerfile` 与 `docker/README.md` 面向的是 `/root/catkin_ws`**（旧工作区）：
   Dockerfile 里 source 的是 `/root/catkin_ws/devel/setup.bash`，README 里的 `docker cp` 示例也是旧路径。
   在新工作区里用这套镜像需要相应改路径。
6. **`aic26_slam/gmapping.launch` 的静态 TF 与 URDF 可能重复**：它把 `base_footprint→laser`
   直接发布为 0.265，而 URDF 链路是 `base_footprint→base_link→support→laser`（数值同样是 0.265）。
   两者数值一致，但若将来又启动了 `robot_state_publisher`，`laser` 会出现两个父坐标系 ——
   **是否产生 TF 告警未实测**，接 RSP 时留意。
7. **`visual_plug/worlds/robot_nav_field.world.bak`** 是备份文件，别误用。
8. **`roscar-gazebo-models` 无 `package.xml`**，`rospack find` 找不到它，`catkin_make` 也不会编译它 ——
   这是设计如此（纯资产仓库），用 `setup.bash` 挂模型路径即可。

---

## 8. 待补齐清单（建议顺序）

1. **`aic26_bringup`**：一个把 `aic26_description` 的 xacro 展开成 `robot_description`、
   spawn 进 `gazebo_test.world`、并起 `robot_state_publisher` + `joint_state_publisher` 的总 launch。
   这是打通 AIC26 栈的第一步，也是 `aic26_navigation` 的前置条件。
2. **`aic26_description`**：补一个类似 `demo06_laser.urdf.xacro` 的总装入口（现在只有
   `gazebo_car_union.xacro`，且没有 launch 引用它）；顺手删掉僵死的 `move.urdf.xacro`。
3. **`aic26_msgs`**：定义任务/目标类消息与 action，同时补 CMakeLists 的
   `add_message_files` / `generate_messages`。
4. **`aic26_navigation`**：把 `nav_demo/param/` 那 4 个 yaml 迁过来并按新底盘改参数
   （尤其 `robot_radius`：旧车 r=0.12，新车是 0.30×0.20 的方盘，圆半径要重算）。
5. **`aic26_slam`**：补地图保存/加载的 launch（对齐 `nav_demo` 的 `nav02` / `nav03`）。
6. **`aic26_perception` / `aic26_ocr`**：模型侧已有 `roscar-gazebo-models/vision_models/`
   （人物检测 + rapidocr 的 ONNX），可直接接。
7. 清理 `src/` 与旧工作区重复的 `nav_demo` / `urdf02_gazebo` / `visual_plug`，
   或明确选定其中一份为准，避免 §7.1 的静默失效。

---

## 9. 命令速查

```bash
# ---- 编译与环境 ----
cd ~/catkin_ws_aic && catkin_make && source devel/setup.bash
export ROS_PACKAGE_PATH=/root/catkin_ws_aic/src:$ROS_PACKAGE_PATH   # 避免旧工作区抢先

# ---- AIC26 ----
roslaunch aic26_gazebo gazebo_test.launch        # 比赛场景（含 armbot，可直接开车）
roslaunch aic26_gazebo model_gallery.launch      # 模型展厅（需先 source roscar setup.bash）
roslaunch aic26_slam  gmapping.launch            # 建图（含 rviz）
source src/roscar-gazebo-models/setup.bash       # 挂上 roscar 模型路径

# ---- 历史导航栈 ----
roslaunch start.launch                           # workdir = 工作区根目录
roslaunch urdf02_gazebo demo03_laser.launch      # 带 /scan 的仿真
roslaunch nav_demo move_test_aic.launch          # 已知地图导航
rosrun map_server map_saver -f /tmp/mymap        # 存地图

# ---- 排查 ----
rostopic list ; rostopic hz /scan ; rostopic hz /odom ; rostopic echo /odom -n1
rospack find nav_demo                            # 确认解析到哪个工作区！
rosservice call /gazebo/get_world_properties     # 看场上有哪些模型
rosrun tf2_tools view_frames.py                  # 生成 frames.pdf 看 TF 树
rosnode list ; rqt_graph
```

## 10. 相关文档

| 文档 | 内容 |
|------|------|
| [src/PROJECT_OVERVIEW.md](src/PROJECT_OVERVIEW.md) | 历史导航栈 `nav_demo` + `urdf02_gazebo` 的逐文件详解、话题/TF 数据流、12 条已知问题 |
| [src/gazebo_ros_model_color/README.md](src/gazebo_ros_model_color/README.md) | 改色插件的上游用法（改色服务的调用示例） |
| [src/roscar-gazebo-models/README.md](src/roscar-gazebo-models/README.md) | 模型库上游文档：模型清单、`install_models.sh`、展厅启动、`GAZEBO_MODEL_PATH` 用法 |
| [docker/README.md](docker/README.md) | Gazebo/RViz 图形显示方案（external / windows / local 三种后端）与容器重建注意事项 |
