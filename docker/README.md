# ROS Noetic + Gazebo 图形界面环境

把"容器里没有 X server 导致 Gazebo GUI 崩溃"这件事**固化进镜像**,重建容器即可自动恢复。

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

> 当前有 5 个未提交改动(`src/pp_learning/src/test815.cpp` 和 4 个 launch 文件)。
> 未提交的东西不会被 `git push` 带走。

---

## 构建镜像

在 `catkin_ws` 目录下(Windows PowerShell 也可以):

```powershell
cd D:\ros\catkin_ws        # 换成你实际的路径
docker build -t ros-noetic-gui docker/
```

**为什么要重建**:当前容器的基础镜像是 `osrf/ros:noetic-desktop-full`,里面没有
`xvfb` / `x11vnc` / `novnc` / `fluxbox` 这些图形依赖 —— 它们是后来手工 `apt install`
进去的,只存在于这个容器的可写层。`Dockerfile` 把这一步固化下来。

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

浏览器打开 **http://localhost:6080/vnc.html**,就能看到 Gazebo 窗口。

自检命令:

```bash
bash /root/display.sh status   # 查看虚拟显示栈各组件状态
bash /root/display.sh check    # 检查 DISPLAY / X 连通性
bash /root/display.sh stop     # 停止显示栈
```

---

## 已有容器里不想重建?

`display.sh` 可以直接拷到任何容器里用,它自带依赖检查:

```bash
# 装依赖
apt-get update && apt-get install -y xvfb x11vnc novnc websockify fluxbox xauth x11-apps x11-utils
# 启用
cp display.sh /root/display.sh && source /root/display.sh
```

---

## 原理(排查问题时看)

**症状**: `[gazebo_gui-N] process has died [exit code 134]`,`gzclient` 连日志文件都来不及生成。

**原因**: 容器里根本没有 X server。环境变量 `DISPLAY=:0` 是从容器 PID 1 继承来的悬空值,
背后没有服务在监听。`gzclient` 创建 GL context 时拿不到 display,OGRE 抛异常 → `abort()`。

**解法**: 用 Xvfb 在 **`:0`** 上跑虚拟显示 —— 刻意选 `:0` 是因为它正是环境变量的既有值,
这样容器里**所有进程天然就是对的**,不依赖任何 shell 配置。

**两个容易搞错的点**:

- 容器无 GPU **不是**崩溃原因。实测不设 `LIBGL_ALWAYS_SOFTWARE` 也能正常渲染
  (约 42 FPS),Mesa 会自动回退到 llvmpipe。`exit 134` 的唯一成因就是没有 X server。
- 容器跑在 Docker Desktop 自己的 `docker-desktop` 发行版里,不是带 WSLg 的那个
  Ubuntu 发行版,所以 `/mnt/wslg/` 不存在 —— **挂载 WSLg 的 X socket 这条路走不通**。

**想用 Windows 原生窗口**而不是浏览器:装 [VcXsrv](https://sourceforge.net/projects/vcxsrv/),
启动时勾选 "Disable access control",`display.sh` 会自动探测到 `host.docker.internal:6000`
并优先复用它,无需改任何配置。
