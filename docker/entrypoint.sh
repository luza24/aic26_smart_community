#!/bin/bash
# 容器启动时的初始化。
#
# 注意: 本文件作为 ENTRYPOINT 会覆盖基础镜像 osrf/ros 自带的 /ros_entrypoint.sh
# (它的作用正是 source /opt/ros/$ROS_DISTRO/setup.bash), 所以这里必须把这一步补回来,
# 否则非交互场景下的 ROS 环境变量会丢。

# 1. ROS 环境 (等价于基础镜像 /ros_entrypoint.sh 的行为)
if [ -f "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash" ]; then
    # shellcheck disable=SC1090
    source "/opt/ros/${ROS_DISTRO:-noetic}/setup.bash"
fi

# 2. 图形显示栈
# 用 source 而非 `display.sh start`: source 会按 external > windows > local 的顺序
# 探测 —— 平台已经挂了可用的 :0 就什么都不启动(实测 Docker Desktop 会把 VM 的
# /.X11-unix 只读挂进来), 否则复用 Windows 侧的 X server, 再否则回退容器内 Xvfb。
# 探测/启动失败不能阻断容器启动, 所以兜了 || true。
source /root/display.sh >/dev/null 2>&1 || true

exec "$@"
