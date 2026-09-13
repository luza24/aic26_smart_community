#!/usr/bin/env bash
# =============================================================================
#  已有容器里的一键环境恢复 (无需重建镜像)
#
#  适用场景: 你不想删容器重建, 或者拿到一个干净的 osrf/ros 容器要快速配好图形环境。
#  脚本是幂等的 —— 重复执行不会破坏已配好的东西。
#
#  用法:
#      bash docker/setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPLAY_SH="$SCRIPT_DIR/display.sh"
TARGET=/root/display.sh

echo "==> 1/4 检查并安装图形依赖"

# xvfb       虚拟显示本体
# x11vnc     虚拟显示导出为 VNC
# novnc      把 VNC 转成浏览器可访问的网页
# websockify novnc 的 websocket 代理
# fluxbox    轻量窗口管理器 (没有它 Gazebo 仍能渲染, 但窗口没有标题栏、不能拖动)
# xauth      配合 Windows 侧 VcXsrv 时需要
# x11-apps   xeyes 等验证用小程序
# x11-utils  xdpyinfo / xwininfo 等诊断工具
# imagemagick 截图 (xwd -> png)
NEEDED=(xvfb x11vnc novnc websockify fluxbox xauth x11-apps x11-utils imagemagick)

MISSING=()
for p in "${NEEDED[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "    全部已安装, 跳过"
else
    echo "    待安装: ${MISSING[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends "${MISSING[@]}"
    echo "    安装完成"
fi

echo "==> 2/4 安装显示配置脚本"

if [[ ! -f "$DISPLAY_SH" ]]; then
    echo "    [x] 找不到 $DISPLAY_SH" >&2
    exit 1
fi

if [[ -f "$TARGET" ]] && cmp -s "$DISPLAY_SH" "$TARGET"; then
    echo "    $TARGET 已是最新, 跳过"
else
    install -m 755 "$DISPLAY_SH" "$TARGET"
    echo "    已安装 -> $TARGET"
fi

echo "==> 3/4 配置 shell 环境"

# 判据是"是否已经有一行在 source /root/display.sh", 而不是某段注释文字 ——
# 否则手工加过等价配置时会被判为"未配置", 造成重复追加。
if grep -qE '^[^#]*source[[:space:]]+/root/display\.sh' /root/.bashrc 2>/dev/null; then
    echo "    .bashrc 已配置, 跳过"
else
    {
        printf '\n# ---- catkin_ws overlay ----\n'
        printf '[ -f /root/catkin_ws/devel/setup.bash ] && source /root/catkin_ws/devel/setup.bash\n'
        printf '\n# ---- Gazebo/RViz 图形显示 ----\n'
        printf '[ -f /root/display.sh ] && source /root/display.sh >/dev/null 2>&1\n'
    } >> /root/.bashrc
    echo "    已追加到 /root/.bashrc"
fi

echo "==> 4/4 启动显示栈"
# shellcheck disable=SC1090
source "$TARGET"

echo
echo "=============================================="
echo " 完成。直接运行, 不需要 source 任何东西:"
echo
echo "     roslaunch urdf02_gazebo demo03_laser.launch"
echo
echo " 浏览器查看: http://localhost:6080/vnc.html"
echo " 状态 / 诊断: bash /root/display.sh status | check"
echo "=============================================="
