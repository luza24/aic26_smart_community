# =============================================================================
#  ROS Noetic + Gazebo 图形界面 开发镜像
#
#  基础镜像 osrf/ros:noetic-desktop-full —— 与当前在用的容器一致
#  (Ubuntu 20.04 focal / ROS noetic desktop-full / Gazebo 11.15.1)
#
#  这个镜像解决两件事:
#    1. 容器内没有 X server 导致 gzclient 报 "exit code 134" 的问题
#    2. 让重建容器后不必再手工敲一堆 apt install
#
#  构建:
#      docker build -t ros-noetic-gui docker/
#
#  启动见 docker/README.md
# =============================================================================
FROM osrf/ros:noetic-desktop-full

# ---- 1. Gazebo / RViz 的图形依赖 ------------------------------------------
# xvfb      容器内虚拟显示 (占用 :0, 与容器环境里既有的 DISPLAY 对齐)
# x11vnc    把虚拟显示导出为 VNC
# novnc     把 VNC 转成浏览器可访问的网页
# websockify novnc 的 websocket 代理
# fluxbox   轻量窗口管理器, 让 Gazebo/RViz 窗口有标题栏且可层叠
# socat     windows 后端: 把容器内的 :0 套接字转发到 Windows 侧 X server,
#           这样 DISPLAY=:0 不用改, 画面却出现在 Windows 桌面上
# xauth     X 认证 (配合 Windows 侧 VcXsrv 时需要)
# x11-apps  xeyes 等验证用小程序
# x11-utils xdpyinfo / xwininfo 等诊断工具
# imagemagick  截图 (xwd -> png), 便于远程确认渲染结果
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        novnc \
        websockify \
        fluxbox \
        socat \
        xauth \
        x11-apps \
        x11-utils \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

# ---- 2. 显示配置脚本 -------------------------------------------------------
COPY display.sh /root/display.sh
RUN chmod +x /root/display.sh

# ---- 3. 容器一起动就拉起虚拟显示 -------------------------------------------
# 首次启动时探测 Windows 侧的 X server(host.docker.internal:6000): 连得上就用
# socat 转发过去(原生窗口), 连不上就起容器内 Xvfb(浏览器查看) —— 两种用法都不用
# 改配置。之后想换后端要显式敲 display.sh windows / local: 切换会停掉另一套,
# 已经跑着的 Gazebo 会跟着挂, 所以不能让它自动发生。
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

# ---- 4. shell 环境 ---------------------------------------------------------
# 工作区 overlay: 不 source 这行 roslaunch 会报
#   "xxx.launch is neither a launch file in package [...] nor is [...] a launch file name"
# 显示配置: 兜底, 保证交互式 shell 里 DISPLAY 一定正确
RUN printf '\n# ---- catkin_ws overlay ----\n[ -f /root/catkin_ws/devel/setup.bash ] && source /root/catkin_ws/devel/setup.bash\n\n# ---- Gazebo/RViz 图形显示 ----\n[ -f /root/display.sh ] && source /root/display.sh >/dev/null 2>&1\n' >> /root/.bashrc

# ---- 5. noVNC 网页入口 -----------------------------------------------------
# 在 Docker Desktop 里要把这个端口映射出来, 浏览器访问 http://localhost:6080/vnc.html
EXPOSE 6080

ENTRYPOINT ["/root/entrypoint.sh"]
CMD ["bash"]
