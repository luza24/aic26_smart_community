#!/usr/bin/env bash
# =============================================================================
#  容器内图形显示配置 —— 让 Gazebo GUI / RViz 能正常渲染
#
#  背景: 容器里 DISPLAY=:0 是个悬空值,背后没有任何 X server,
#        导致 gzclient 在创建 GL context 时 abort (exit code 134 / SIGABRT)。
#        本脚本解决"显示"和"渲染"两件事:
#          1. 显示 —— 优先复用 Windows 侧的 X server; 连不上就在容器内起 Xvfb 虚拟显示
#          2. 渲染 —— 容器无 GPU 直通, 强制 LIBGL_ALWAYS_SOFTWARE=1 走 llvmpipe 软件渲染
#
#  用法:
#      source /root/display.sh          # 配置当前 shell (需要时自动拉起虚拟显示)
#      /root/display.sh start           # 只启动虚拟显示栈
#      /root/display.sh stop            # 停止虚拟显示栈
#      /root/display.sh status          # 查看状态
#      /root/display.sh check           # 环境自检
# =============================================================================

# 仅在"直接执行"时收紧 shell 选项。被 source 时绝不能设 —— set -u 会让调用方
# 交互 shell 里任何未定义变量引用直接报错 (比如常见的 $PS1 / $PROMPT_COMMAND 用法)。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -uo pipefail
fi

# ---- 可调参数 ---------------------------------------------------------------
EXT_HOST="${EXT_HOST:-host.docker.internal}"   # Windows 侧 X server 地址
EXT_PORT="${EXT_PORT:-6000}"                   # X TCP 端口: :0 对应 6000
# 刻意占用 :0 —— 容器 PID 1 的环境里 DISPLAY 就是 ":0", 所有进程都继承它。
# 让虚拟显示直接顶替这个号, 环境变量天然正确, 不再依赖每个 shell 都 source 本脚本。
XVFB_DISPLAY_NUM="${XVFB_DISPLAY_NUM:-0}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-6080}"
GEOMETRY="${GEOMETRY:-1600x900x24}"

VDISP=":${XVFB_DISPLAY_NUM}"
RUNDIR="/tmp/display-stack"
LOG="$RUNDIR/log"

# ---- 工具函数 ---------------------------------------------------------------
# 探测某个 host:port 上是否有 X server 在监听
x_reachable() {
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null
}

# 某个进程是否还活着 (读 pidfile)
alive() {
    local f="$RUNDIR/$1.pid"
    [[ -f "$f" ]] && kill -0 "$(cat "$f")" 2>/dev/null
}

# 后台常驻启动一个组件。用法: spawn <标签> <命令> [参数...]
# 标签与命令必须都传: 若写成 spawn fluxbox (标签=命令), shift 后 $@ 为空,
# nohup 会收到零个操作数并以 "nohup: missing operand" 静默失败。
spawn() {
    local name="$1"; shift
    if [[ $# -eq 0 ]]; then
        echo "[x] spawn 调用错误: '$name' 缺少要执行的命令" >&2
        return 1
    fi
    # 用 exec 让记录下来的 PID 就是最终进程的 PID。
    # 直接 echo $! 记的是 setsid 的 PID, 而 setsid 在自身已是进程组长时会 fork 后退出,
    # 导致 pidfile 指向一个已死进程, liveness 判断失真、组件被重复拉起。
    setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' \
        bash "$RUNDIR/$name.pid" "$@" >>"$LOG/$name.log" 2>&1 &
    # 等 pidfile 落盘
    local i
    for i in $(seq 1 25); do [[ -s "$RUNDIR/$name.pid" ]] && return 0; sleep 0.2; done
    return 0
}

start_stack() {
    mkdir -p "$LOG"

    # 1. Xvfb —— 虚拟显示本体
    if ! alive xvfb; then
        command -v Xvfb >/dev/null || { echo "[x] 缺少 Xvfb, 请先: apt-get install -y xvfb x11vnc novnc websockify fluxbox"; return 1; }
        spawn xvfb Xvfb "$VDISP" -screen 0 "$GEOMETRY" -ac +extension GLX +render -noreset
        # 等 X socket 就绪
        for _ in $(seq 1 30); do
            [[ -S "/tmp/.X11-unix/X${XVFB_DISPLAY_NUM}" ]] && break
            sleep 0.2
        done
        [[ -S "/tmp/.X11-unix/X${XVFB_DISPLAY_NUM}" ]] || { echo "[x] Xvfb 启动失败, 见 $LOG/xvfb.log"; return 1; }
        echo "[+] Xvfb       $VDISP ($GEOMETRY)"
    else
        echo "[=] Xvfb       $VDISP 已在运行"
    fi

    # 2. fluxbox —— 轻量窗口管理器。没有 WM 时 Gazebo 仍能渲染 (Qt 自绘菜单栏),
    #    但窗口没有标题栏、无法拖动/层叠; 同时开 Gazebo 和 RViz 时会互相盖住
    if ! alive fluxbox; then
        export DISPLAY="$VDISP"
        spawn fluxbox fluxbox
        echo "[+] fluxbox    窗口管理器"
    fi

    # 3. x11vnc —— 把虚拟显示导出为 VNC。只绑 localhost, 由 websockify 做唯一入口
    if ! alive x11vnc; then
        spawn x11vnc x11vnc -display "$VDISP" -localhost -nopw -forever -shared \
              -rfbport "$VNC_PORT" -quiet
        echo "[+] x11vnc     127.0.0.1:$VNC_PORT"
    else
        echo "[=] x11vnc     127.0.0.1:$VNC_PORT 已在运行"
    fi

    # 4. websockify + noVNC —— 把 VNC 转成浏览器可访问的网页
    if ! alive noVNC; then
        spawn noVNC websockify --web=/usr/share/novnc/ "$WEB_PORT" "localhost:$VNC_PORT"
        echo "[+] noVNC      0.0.0.0:$WEB_PORT"
    else
        echo "[=] noVNC      0.0.0.0:$WEB_PORT 已在运行"
    fi
}

stop_stack() {
    local n
    for n in noVNC x11vnc fluxbox xvfb; do
        if alive "$n"; then
            kill "$(cat "$RUNDIR/$n.pid")" 2>/dev/null
            echo "[-] 已停止 $n"
        fi
        rm -f "$RUNDIR/$n.pid"
    done
}

status_stack() {
    local n
    for n in xvfb fluxbox x11vnc noVNC; do
        printf "%-10s " "$n"
        if alive "$n"; then echo "运行中 (pid $(cat "$RUNDIR/$n.pid"))"; else echo "未运行"; fi
    done
    echo
    x_reachable "$EXT_HOST" "$EXT_PORT" \
        && echo "外部 X server ($EXT_HOST:$EXT_PORT): 可达" \
        || echo "外部 X server ($EXT_HOST:$EXT_PORT): 不可达 —— 会回退到容器内虚拟显示"
}

# ---- 主流程 ----------------------------------------------------------------
# 这份脚本既可 source 也可直接执行; 直接执行时用 return/exit 区分
_is_sourced() { [[ "${BASH_SOURCE[0]}" != "${0}" ]]; }

case "${1:-auto}" in
    stop)    stop_stack; _is_sourced || exit 0; return 0 ;;
    status)  status_stack; _is_sourced || exit 0; return 0 ;;
    check)   ;;
    start|auto|"") ;;
    *) echo "用法: source /root/display.sh | $0 {start|stop|status|check}"; _is_sourced || exit 2; return 2 ;;
esac

if x_reachable "$EXT_HOST" "$EXT_PORT"; then
    MODE="外部 X server"
    export DISPLAY="${EXT_HOST}:0"
else
    MODE="容器内虚拟显示"
    start_stack || { _is_sourced || exit 1; return 1; }
    export DISPLAY="$VDISP"
fi

# 下面两个是"保险"而非"必需": 实测在 Xvfb 存在的前提下, 即使不设这两个变量,
# Mesa 也会自行回退到 llvmpipe 软件渲染 (Gazebo 约 42 FPS)。gzclient 的 exit 134
# 唯一成因就是没有 X server, 与渲染后端无关。显式设上只是避免将来换环境时
# Mesa 误选 GPU 路径。
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"

if [[ "${1:-auto}" == "check" ]]; then
    echo "  模式        : $MODE"
    echo "  DISPLAY     : $DISPLAY"
    echo "  软件渲染    : LIBGL_ALWAYS_SOFTWARE=$LIBGL_ALWAYS_SOFTWARE  GALLIUM_DRIVER=$GALLIUM_DRIVER"
    echo
    echo "--- X server 连通性 ---"
    if xdpyinfo -display "$DISPLAY" 2>&1 | grep -E '^(name of display|dimensions|depth of root)' ; then
        echo "--- [OK] X 连接正常 ---"
    else
        echo "--- [x] 连不上 $DISPLAY ---"
    fi
    echo
    echo "浏览器查看(容器内虚拟显示模式): http://localhost:$WEB_PORT/vnc.html"
else
    echo "显示已就绪: $MODE  →  DISPLAY=$DISPLAY"
    [[ "$MODE" == "容器内虚拟显示" ]] && \
        echo "浏览器打开            : http://localhost:$WEB_PORT/vnc.html"
    echo "现在可以直接: roslaunch urdf02_gazebo demo03_laser.launch"
fi
