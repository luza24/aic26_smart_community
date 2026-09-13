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
# 用 source 而非 `display.sh start`: source 会先探测 Windows 侧的 X server
# (host.docker.internal:6000), 连得上就复用它, 连不上才回退到容器内 Xvfb。
# 探测/启动失败不能阻断容器启动, 所以兜了 || true。
source /root/display.sh >/dev/null 2>&1 || true

exec "$@"
