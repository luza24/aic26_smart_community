# Gazebo GUI 启动崩溃排查记录

> 2026-09-13 · 容器 `fb6cdea60c2e` · 环境 Ubuntu 20.04 / ROS Noetic / Gazebo 11.15.1

## 1. 问题现象

`roslaunch urdf02_gazebo demo03_laser.launch` 后,Gazebo 图形界面起不来:

```
[INFO] ... waitForService: Service [/gazebo_gui/set_physics_properties] has not been advertised, waiting...
Aborted
[gazebo_gui-3] process has died [pid 1724, exit code 134, cmd .../gazebo_ros/gzclient ...].
log file: /root/.ros/log/<run_id>/gazebo_gui-3*.log
```

关键细节:

- **`exit code 134`** = 128 + SIGABRT(6),进程收到 `abort()`
- **`gazebo_gui-3.log` 这个文件根本不存在** —— 崩溃发生在日志系统初始化之前
- **`gzserver` 完全正常**:物理引擎、Laser 插件、DiffDrive 插件、模型 spawn 全部成功
- **`model-4`(spawn_model)正常退出** —— 模型确实进了仿真世界

也就是说:**仿真本身是好的,坏的只有图形界面。**

## 2. 根因

**容器里没有任何 X server。** 环境变量 `DISPLAY=:0` 是个悬空值 —— 变量被设上了,
背后没有服务在监听。`gzclient` 创建 OpenGL context 时拿不到 display,OGRE 抛异常,
`abort()`。

证据链:

| 检查项 | 结果 |
|---|---|
| `$DISPLAY` | `:0`(从容器 PID 1 继承) |
| `/tmp/.X11-unix/` | 存在但**空的**,没有 `X0` socket |
| `/mnt/wslg/` | **不存在** → WSLg 不可用 |
| `host.docker.internal:6000` | Connection refused |
| `172.17.0.1:6000` | Connection refused |

## 3. 环境限制(决定了哪些方案可行)

```
HOSTNAME=docker-desktop        ← 容器跑在 Docker Desktop 自己的发行版里
PID 1 = bash                   ← 不是 init 系统
无 /workspaces                 ← 不是标准 devcontainer 工作区
容器内无 docker CLI             ← 镜像构建只能在 Windows 侧做
```

**推论:挂载 WSLg 的 X socket 这条路走不通。**
WSLg 的 X socket 只活在用户那个 Ubuntu 发行版里,而容器跑在 Docker Desktop 的
`docker-desktop` 发行版中,`/mnt/wslg/` 根本不存在 —— 挂 `/tmp/.X11-unix` 挂到的是空气。

## 4. 走过的弯路(重要,避免重复踩)

### 4.1 误判一:`LIBGL_ALWAYS_SOFTWARE=1` 是必需的

一度认为"容器无 GPU,必须强制软件渲染,否则 OGRE 照样 abort"。

**实测证伪**:在 Xvfb 存在的前提下,不设这个变量 Gazebo 照样渲染,
**42.30 FPS**(设了之后 43.90 FPS,基本一致)。Mesa 在没有 GPU 时会自动回退到 llvmpipe。

**`exit code 134` 的唯一成因就是没有 X server,与渲染后端无关。**

脚本里仍保留这两个变量,但定位是"保险而非必需"。

### 4.2 误判二:假阳性"进程存活"检查

用 `pgrep -f '[g]zclient'` 判断存活,结果**匹配到了执行命令的 shell 自己** ——
因为命令里有一句 `echo "gzclient 存活"`,这个字符串就在 shell 的命令行上。
于是报告"gzclient 存活",而实际上 Gazebo 因为 `RLException` 根本没启动。

**教训**:判断进程存活一律用 `pgrep -x <进程名>`(精确匹配进程名,不匹配命令行)。

### 4.3 同类坑:`pkill` 杀掉了自己

`pkill -f 'gzserver'` 会杀掉执行命令的 shell —— 同理,命令行里含该字符串。

**规避**:用 `pgrep -x`,或写成 `'[g]zserver'` 这种自规避正则,
或把清理逻辑放进**独立的脚本文件**(调用方命令行里就不出现这些字面量)。

### 4.4 `roslaunch` 报找不到包

```
RLException: [demo03_laser.launch] is neither a launch file in package [urdf02_gazebo] ...
```

**原因**:没 source 工作区 overlay。`/root/.bashrc` 里只 source 了
`/opt/ros/noetic/setup.bash`,不含 `/root/catkin_ws/devel/setup.bash`。
`.bashrc` 已补上这一行。

### 4.5 `spawn fluxbox` 静默失败

封装的 `spawn <标签> <命令> [参数...]` 函数,把 `$1` 当标签吃掉再 `shift`。
其他组件调用形如 `spawn xvfb Xvfb :1 ...`(标签≠命令),而 fluxbox 写成了
`spawn fluxbox` —— 标签与命令同名,`shift` 后 `$@` 为空:

```
nohup: missing operand
```

**fluxbox 从头到尾就没跑起来过。** 已加参数校验。

副作用值得记录:没有窗口管理器时 Gazebo **仍能正常渲染**(Qt 自绘菜单栏),
所以肉眼看截图发现不了问题 —— 只是窗口没有标题栏、不能拖动、多窗口时互相盖住。

### 4.6 pidfile 记错 PID

`setsid ... &` 之后用 `echo $!` 记 PID,记到的是 `setsid` 的 PID。
`setsid` 在自身已是进程组长时会 **fork 后退出**,pidfile 于是指向一个死进程,
导致存活判断失真、组件被重复拉起。

**修法**:`setsid bash -c 'echo $$ > pidfile; shift; exec "$@"'` —— 先写 PID 再 `exec`,
记下来的就是最终进程的 PID。

### 4.7 `.bashrc` 方案的根本缺陷

最初把 Xvfb 跑在 `:1`,靠 `.bashrc` 里 `source display.sh` 来设 `DISPLAY=:1`。

**缺陷**:只有 source 过脚本的 shell 才正确。从 VS Code 任务、`docker exec`、
脚本里启动的进程拿到的还是 `:0`,照样崩。

**这正是"用户明明已经修复了却还是崩溃"的原因** —— 他的终端开在 `.bashrc` 被修改**之前**,
旧终端不会重新读取 `.bashrc`。

### 4.8 `source` 污染调用方 shell

`display.sh` 顶部的 `set -uo pipefail` 在被 `source` 时会作用到交互 shell 上,
`set -u` 会让任何未定义变量引用直接报错。

**修法**:仅当 `"${BASH_SOURCE[0]}" == "${0}"`(直接执行)时才设置。

## 5. 最终方案

### 5.1 核心思路:Xvfb 占用 `:0`

**容器 PID 1 的环境里 `DISPLAY` 就是 `:0`,所有进程都继承它。**
让虚拟显示直接顶替这个号,环境变量天然正确 —— **不依赖任何 shell 配置**。

这是整个方案的关键。跑在 `:1` 上就需要每个 shell 都正确 source,永远治不干净。

### 5.2 显示栈

| 组件 | 作用 | 监听 |
|---|---|---|
| `Xvfb :0` | 虚拟显示本体,`1600x900x24` | `/tmp/.X11-unix/X0` |
| `fluxbox` | 轻量窗口管理器 | — |
| `x11vnc` | 虚拟显示导出为 VNC | 仅 `127.0.0.1:5900`(由 websockify 做唯一入口) |
| `websockify` + noVNC | VNC 转网页 | `0.0.0.0:6080` |

浏览器访问 **http://localhost:6080/vnc.html**。

### 5.3 用法

```bash
roslaunch urdf02_gazebo demo03_laser.launch     # 直接跑, 无需 source 任何东西

bash /root/display.sh status   # 查看各组件状态
bash /root/display.sh check    # 检查 DISPLAY / X 连通性
bash /root/display.sh start    # 只启动显示栈
bash /root/display.sh stop     # 停止显示栈
```

脚本会自动探测 Windows 侧的 X server(`host.docker.internal:6000`):
连得上就复用它(原生窗口),连不上才回退到容器内 Xvfb(浏览器查看)。两种用法都不用改配置。

## 6. 验证结果

```
继承来的 DISPLAY      = :0        ← 完全不 source display.sh, 只用继承环境
LIBGL_ALWAYS_SOFTWARE = <未设>

gzclient : 存活
gzserver : 存活
日志中 died/abort 次数 : 0
```

虚拟显示上的窗口树:

```
0x1400012 "Gazebo": ("gazebo" "gazebo")  1066x516+0+0
```

截图确认渲染正常:世界、障碍物圆柱、激光雷达蓝色扇形扫描全部呈现,
标题栏由 fluxbox 提供,**Real Time Factor 1.00 / FPS 42~44**。

## 7. 固化

见 `docker/Dockerfile` + `entrypoint.sh` + `display.sh`。
基础镜像 `osrf/ros:noetic-desktop-full`(靠 `/ros_entrypoint.sh` 标志文件判定)。

### 7.1 覆盖基础镜像 ENTRYPOINT 的陷阱

`osrf/ros` 自带 `ENTRYPOINT ["/ros_entrypoint.sh"]`,而它的作用正是
`source /opt/ros/$ROS_DISTRO/setup.bash`。

**自己的 entrypoint 一旦覆盖它,非交互场景下 ROS 环境变量就丢了。**
`entrypoint.sh` 里已把这一步补回来。

## 8. 遗留问题

- **`/root/catkin_ws` 不是挂载卷**,代码活在容器可写层。重建容器会丢失整个工作区 ——
  **必须**先 `docker cp` 出来或推送到 GitHub,并在新容器上挂 `-v`。这是比 Dockerfile
  更要紧的事。
- 容器内无 docker CLI,**镜像构建无法在容器内验证**,需在 Windows 侧执行。
- 虚拟显示栈是常驻进程,容器重启后靠 `entrypoint.sh` / `.bashrc` 拉起。

## 9. 快速诊断清单

遇到 Gazebo GUI 起不来,按顺序查:

```bash
# 1. 有没有 X server 在监听 DISPLAY 指向的地方
echo "DISPLAY=$DISPLAY"
xdpyinfo -display "$DISPLAY" | head -3

# 2. X socket 存不存在
ls -la /tmp/.X11-unix/

# 3. 显示栈是否在跑 (必须用 -x, 不能用 -f)
for p in Xvfb fluxbox x11vnc; do printf "%-10s " $p; pgrep -x $p >/dev/null && echo 在跑 || echo 没跑; done

# 4. 包路径对不对
rospack find urdf02_gazebo

# 5. 直接看浏览器入口通不通
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:6080/vnc.html
```
