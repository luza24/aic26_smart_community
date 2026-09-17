# ROS Noetic + Gazebo 图形界面环境

把"容器里没有可用的 X server 导致 Gazebo GUI 崩溃"这件事**固化进镜像**,重建容器即可自动恢复。

**先跑这一条,再决定要不要往下看:**

```bash
xdpyinfo -display :0 >/dev/null 2>&1 && echo "':0' 已经能用" || echo "需要配显示栈"
```

显示"已经能用"(当前这台 Docker Desktop 就是这样)的话,**什么都不用做** —— 窗口会直接
出现在 Windows 桌面上,下面全是它失灵时的退路。

三个后端互斥、随时可切,都**不需要改 `DISPLAY`**;优先级从高到低:

| 后端 | 谁在服务 `:0` | 画面出现在 | 切换命令 |
|---|---|---|---|
| **external** | 平台自己挂进来的(只读 `/tmp/.X11-unix/X0`) | Windows 桌面,原生窗口 | 自动,不用敲命令 |
| **windows** | `socat` → Windows 侧 VcXsrv | Windows 桌面,原生窗口 | `bash /root/display.sh windows` |
| **local** | 容器内 `Xvfb` + noVNC | 浏览器 `http://localhost:6080/vnc.html` | `bash /root/display.sh local` |

自动模式**永远优先用现成的**:平台给了 `:0` 就用它,没有再试 VcXsrv,最后才自己起 Xvfb。
`local` / `windows` 是强制切 —— 平台已经给了能用的 `:0` 时,这两个命令会直接报错并说明
原因(硬起也起不来,抢不到 socket),而不是留下一个"看起来启动了"的假象。

想在不依赖平台的情况下直接在 Windows 桌面上看窗口,跳到[路线 B](#路线-b让-gazebo-窗口出现在-windows-桌面上)。

---

## ⚠️ 先做这一步:把代码搬出容器

**你的 `/root/catkin_ws` 目前不是挂载卷,它活在容器的可写层里。**
一旦在 Docker Desktop 里删掉容器重建(换镜像必须这么做),**整个工作区会一起消失**。

在 Windows 的 PowerShell 里执行,把代码拷到宿主机:

```powershell
# 容器 ID 前几位即可, 你当前这个容器是 fb6cdea60c2e
docker cp fb6cdea60c2e:/root/catkin_ws D:\ros\catkin_ws
```

或者先把改动提交推送到 GitHub,再在宿主机上 clone:

```bash
# 在容器里执行
cd /root/catkin_ws
git add -A && git commit -m "保存当前改动"
git push origin2 master      # 或 git push origin master
```

> 未提交的东西不会被 `git push` 带走。删容器前先 `git status` 确认工作区是干净的。

---

## 构建镜像

在 `catkin_ws` 目录下(Windows PowerShell 也可以):

```powershell
cd D:\ros\catkin_ws        # 换成你实际的路径
docker build -t ros-noetic-gui docker/
```

**为什么要重建**:当前容器的基础镜像是 `osrf/ros:noetic-desktop-full`,里面没有
`xvfb` / `x11vnc` / `novnc` / `fluxbox` / `socat` 这些图形依赖 —— 它们是后来手工
`apt install` 进去的,只存在于这个容器的可写层。`Dockerfile` 把这一步固化下来。

---

## 在 Docker Desktop 里启动

镜像构建完成后,在 Docker Desktop 的 **Images** 页找到 `ros-noetic-gui`,
点 **Run**,展开 **Optional settings**,填两项:

| 设置项 | 值 | 说明 |
|---|---|---|
| **Host port** | `6080` | noVNC 网页入口,容器端口也填 `6080` |
| **Host path** | `D:\ros\catkin_ws` | 换成你上一步 `docker cp` 出来的实际路径 |
| **Container path** | `/root/catkin_ws` | 挂到这里,ROS 包路径才对 |

命令行等价写法(想用命令行启动的话):

```bash
docker run -it --rm \
  -p 6080:6080 \
  -v D:/ros/catkin_ws:/root/catkin_ws \
  --name ros_gui \
  ros-noetic-gui
```

**`-v` 挂载是关键**:挂上之后代码就活在宿主机上,以后无论怎么删容器重建,
代码都不会丢。这才是这个方案真正"根治"的地方。

---

## 验证

容器起来后直接跑,不需要 `source` 任何东西:

```bash
roslaunch urdf02_gazebo demo03_laser.launch
```

看画面 — 取决于当前后端:

- **external**:窗口直接在 Windows 桌面上(平台自己给的 `:0`,什么组件都没起)
- **local**:浏览器打开 **http://localhost:6080/vnc.html**
- **windows**(见[路线 B](#路线-b让-gazebo-窗口出现在-windows-桌面上)):窗口直接在 Windows 桌面上

自检命令:

```bash
bash /root/display.sh status   # 各组件状态 / :0 现在是谁在服务 / 当前后端 / Windows X 是否可达
bash /root/display.sh check    # 检查 DISPLAY / X 连通性 / 各工具是否装齐
bash /root/display.sh stop     # 停止显示栈 (不会碰平台挂进来的 X0)
```

---

## 已有容器里不想重建?

不用重建,一条命令搞定 —— `setup.sh` 会装依赖、装 `display.sh`、配好 `.bashrc`、
拉起显示栈,并且是**幂等**的(重复跑不会破坏已配好的东西):

```bash
bash docker/setup.sh
```

拿到一个干净的 `osrf/ros` 容器要快速配好图形环境,也是跑这条。

---

## 装 ROS 包:前缀是 `ros-noetic-*`,不是 `ros-melodic-*`

本容器是 **Ubuntu 20.04 (focal) + ROS Noetic**,apt 包名的前缀跟着发行版走:

```bash
sudo apt-get install ros-noetic-depthimage-to-laserscan
```

网上教程里**大量**写的是 `ros-melodic-xxx`(Melodic 跨 2018~2023,是教程存量最大的一代,
但它对应 Ubuntu 18.04)。照抄到本容器上会得到:

```
E: Unable to locate package ros-melodic-xxx
```

**这不代表包不存在、也不代表源坏了**,只是前缀不对,不用改源也不用 `apt-get update`。
查正确包名:

```bash
echo "$ROS_DISTRO"                                  # → noetic
apt-cache search "^ros-${ROS_DISTRO}-" | grep -i <关键字>
```

完整排查过程见 `TROUBLESHOOTING.md` §11。

---

## 原理(排查问题时看)

**症状**: `[gazebo_gui-N] process has died [exit code 134]`,`gzclient` 连日志文件都来不及生成。

**原因**: `:0` 背后没有服务在监听。环境变量 `DISPLAY=:0` 是从容器 PID 1 继承来的悬空值,
`gzclient` 创建 GL context 时拿不到 display,OGRE 抛异常 → `abort()`。

**解法**: 让 **`:0`** 上真的有一个 X server —— 刻意选 `:0` 是因为它正是环境变量的既有值,
这样容器里**所有进程天然就是对的**,不依赖任何 shell 配置。至于谁来提供它:

- 平台/环境已经给了 → 直接用,什么都别启动(`external`)
- 没有 → 用 socat 把 `:0` 转发到 Windows 侧真实的 X server(`windows`)
- 再没有 → 容器内起一个 Xvfb(`local`)

**两个容易搞错的点**:

- 容器无 GPU **不是**崩溃原因。实测不设 `LIBGL_ALWAYS_SOFTWARE` 也能正常渲染
  (约 42 FPS),Mesa 会自动回退到 llvmpipe。`exit 134` 的唯一成因就是没有 X server。
- `/mnt/wslg/` 确实不存在(容器跑在 Docker Desktop 自己的 `docker-desktop` 发行版里,
  不是带 WSLg 的那个 Ubuntu 发行版),但那**不等于**容器里没有 X server ——
  平台会把 VM 的 `/.X11-unix` **只读挂**进容器的 `/tmp/.X11-unix`,实测 `:0` 上有活的
  server,分辨率就是 Windows 屏幕分辨率,还带着窗口管理器。
  判断"有没有"看 `xdpyinfo -display :0` 通不通、`findmnt -T /tmp/.X11-unix` 是不是
  `ro` 挂载,**不要看 `/mnt/wslg/` 在不在**。

---

## 路线 B:让 Gazebo 窗口出现在 Windows 桌面上

> 先确认一下:如果 `xdpyinfo -display :0` 已经通,说明平台自己给了 `:0`,**这一整条路线
> 都不需要** —— 窗口本来就在 Windows 桌面上。路线 B 是平台没给、或者你想摆脱这层依赖
> 时的备选。

默认的 local 后端是把画面渲染进容器内部的一块虚拟屏幕,再用 noVNC 导出成网页 ——
所以**你在 Windows 桌面上是看不到 Gazebo 窗口的**,得开浏览器。想让窗口像普通
Windows 程序那样直接弹在桌面上,用 windows 后端。

### 1. 在 Windows 上装 VcXsrv

下载 <https://sourceforge.net/projects/vcxsrv/> 并安装(一路 Next 即可)。

### 2. 配置并启动 XLaunch

从开始菜单打开 **XLaunch**,按下面四项设置:

| 页面 | 选项 |
|---|---|
| Display settings | **Multiple windows**,Display number 填 `0` |
| Client startup | **Start no client** |
| Extra settings | 勾上 **Disable access control** ← 不勾容器连不上 |
| | 勾上 **Clipboard**(可选,让容器和 Windows 之间能复制粘贴) |

最后点 **Save configuration**,存成桌面快捷方式,以后双击它启动就行。

### 3. 放行防火墙

第一次启动时 Windows 会弹防火墙询问,**专用网络和公用网络两个都要勾上**。
如果当时点了"取消",画面会连不上,手动补一次:

> 控制面板 → 系统和安全 → Windows Defender 防火墙 → 允许应用通过防火墙
> → 找到 `vcxsrv.exe` → 把"专用"和"公用"两列都勾上

### 4. 切到 windows 后端

VcXsrv 跑起来之后,在容器里执行:

```bash
bash /root/display.sh windows
```

看到 `[+] socat  /tmp/.X11-unix/X0 -> 192.168.65.254:6000` 就成了。然后照常:

```bash
roslaunch urdf02_gazebo demo03_laser.launch
```

Gazebo 的窗口会直接出现在 Windows 桌面上。想切回浏览器模式:`bash /root/display.sh local`。

### 为什么不用改 DISPLAY

X server 的选址是靠 `DISPLAY` 环境变量里的**显示号**决定的 —— `:0` 对应
`/tmp/.X11-unix/X0` 这个 unix socket。直觉做法是把 `DISPLAY` 改成
`host.docker.internal:0` 直接指向 Windows,但那样**每一处**用到图形的地方
(交互式 shell、VS Code 任务、`docker exec` 进来的命令、launch 文件里起的节点)
都得跟着改,漏一个就又是一次 `exit code 134`。

这里换个方向:**不动 `DISPLAY`**,而是让 socat 顶替 `:0` 那个 socket,
把到达它的连接转发到 Windows 的 6000 端口。

```
容器内的进程  →  /tmp/.X11-unix/X0  →  socat  →  TCP 192.168.65.254:6000  →  VcXsrv
               (DISPLAY=:0)                                 (host.docker.internal)
```

于是 `DISPLAY=:0` 在三种后端下**都天然正确**,零 shell 配置。

两个实现细节:

- 必须显式取 **IPv4**。`host.docker.internal` 同时解析出 IPv6(`fdc4:f303:9324::254`)
  和 IPv4(`192.168.65.254`),而 socat 优先用 IPv6,Windows 侧的 VcXsrv 又只监听
  IPv4 —— 不强制 IPv4 会永远连不上。脚本里用 `getent ahostsv4` 解决。
- 后端的**切换会先停掉另一个**(windows 与 local 抢同一个 socket 路径)。为了不让你
  开个新终端就把正在跑的 Gazebo 弄挂,`display.sh` 在自动模式下**已经跑着就不切换** ——
  想换后端要显式敲 `windows` / `local`。删那个 socket 之前会先确认"是本脚本建的、
  且没有别的活着的 server 在用",平台挂进来的只读 `X0` 一律不碰。

### 排查

```bash
bash /root/display.sh status          # 看 socat 在不在、Windows X 可不可达
bash /root/display.sh check           # 看 DISPLAY 连不连得上
tail -20 /tmp/display-stack/log/socat.log
```

| 现象 | 原因 |
|---|---|
| `连不上 host.docker.internal:6000` | VcXsrv 没启动,或防火墙没放行 |
| status 显示"不可达"但 socat 在跑 | VcXsrv 被关掉了,重启它即可,不用动容器 |
