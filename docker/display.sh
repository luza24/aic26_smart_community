#!/usr/bin/env bash
# =============================================================================
#  容器内图形显示配置 —— 让 Gazebo GUI / RViz 能正常渲染
#
#  背景: 容器里 DISPLAY=:0 是个悬空值, 背后没有任何 X server,
#        导致 gzclient 在创建 GL context 时 abort (exit code 134 / SIGABRT)。
#
#  两种后端, 都服务于 :0 —— 所以环境变量 DISPLAY=:0 在两种模式下都天然正确,
#  不依赖任何 shell 配置:
#
#    local    Xvfb 在容器内起一块虚拟屏幕。画面用浏览器看 (noVNC)。
#    windows  用 socat 把容器内的 :0 套接字转发到 Windows 侧的 X server (VcXsrv)。
#             画面直接出现在 Windows 桌面上, 且无需改 DISPLAY。
#
#  用法:
#      source /root/display.sh          # 自动选后端 (windows 可达则优先 windows)
#      /root/display.sh start           # 同上, 只做启动不做 shell 配置
#      /root/display.sh windows         # 强制切到 Windows 侧 X server
#      /root/display.sh local           # 强制切回容器内虚拟显示
#      /root/display.sh stop            # 停止全部
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
EXT_PORT="${EXT_PORT:-6000}"                   # X TCP 端口: 显示号 :N 对应 6000+N
# 刻意占用 :0 —— 容器 PID 1 的环境里 DISPLAY 就是 ":0", 所有进程都继承它。
# 让显示后端直接顶替这个号, 环境变量天然正确。
DISP_NUM="${DISP_NUM:-0}"
VNC_PORT="${VNC_PORT:-5900}"
WEB_PORT="${WEB_PORT:-6080}"
GEOMETRY="${GEOMETRY:-1600x900x24}"

VDISP=":${DISP_NUM}"
XSOCK="/tmp/.X11-unix/X${DISP_NUM}"
RUNDIR="/tmp/display-stack"
LOG="$RUNDIR/log"
MODEFILE="$RUNDIR/backend"

# ---- 工具函数 ---------------------------------------------------------------
# 取 host.docker.internal 的 IPv4 地址。必须显式取 IPv4 —— 该名字同时解析出
# IPv6 (fdc4:...), socat 会优先用 IPv6, 而 Windows 侧的 VcXsrv 通常只监听 IPv4,
# 走 IPv6 会永远连不上。
host_ip4() {
    getent ahostsv4 "$EXT_HOST" 2>/dev/null | awk 'NR==1{print $1}'
}

# Windows 侧 X server 是否可达 (按 IPv4 试连)
ext_reachable() {
    local ip="$1"
    [[ -n "$ip" ]] || return 1
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/$EXT_PORT" 2>/dev/null
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
    local i
    for i in $(seq 1 25); do [[ -s "$RUNDIR/$name.pid" ]] && return 0; sleep 0.2; done
    return 0
}

kill_component() {
    local n="$1"
    if alive "$n"; then
        kill "$(cat "$RUNDIR/$n.pid")" 2>/dev/null
        echo "[-] 已停止 $n"
    fi
    rm -f "$RUNDIR/$n.pid"
}

# ---- local 后端:容器内 Xvfb ------------------------------------------------
stop_local() {
    local n
    for n in noVNC x11vnc fluxbox xvfb; do kill_component "$n"; done
}

start_local() {
    mkdir -p "$LOG"

    # 先停掉 windows 后端的转发 —— 否则切回来时 socat 残留, 还占着 X0 socket
    stop_windows

    # 1. Xvfb —— 虚拟显示本体
    if ! alive xvfb; then
        command -v Xvfb >/dev/null || { echo "[x] 缺少 Xvfb, 请先: bash docker/setup.sh"; return 1; }
        spawn xvfb Xvfb "$VDISP" -screen 0 "$GEOMETRY" -ac +extension GLX +render -noreset
        local _
        for _ in $(seq 1 30); do
            [[ -S "$XSOCK" ]] && break
            sleep 0.2
        done
        [[ -S "$XSOCK" ]] || { echo "[x] Xvfb 启动失败, 见 $LOG/xvfb.log"; return 1; }
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

    echo local > "$MODEFILE"
}

# ---- windows 后端:socat 转发到 VcXsrv --------------------------------------
stop_windows() {
    kill_component socat
    rm -f "$XSOCK"
}

start_windows() {
    mkdir -p "$LOG"
    local ip; ip="$(host_ip4)"

    if [[ -z "$ip" ]]; then
        echo "[x] 解析不出 $EXT_HOST 的 IPv4 地址"
        return 1
    fi
    if ! ext_reachable "$ip"; then
        echo "[x] $EXT_HOST:$EXT_PORT ($ip) 连不上"
        echo "    → 检查 Windows 侧 VcXsrv 是否已启动, 以及防火墙是否放行 (专用+公用都要勾)"
        return 1
    fi

    # Xvfb 占着同一个 socket 路径, 必须先停掉, 否则 socat 绑不上
    stop_local
    rm -f "$XSOCK"

    if ! alive socat; then
        spawn socat socat \
            "UNIX-LISTEN:${XSOCK},fork,mode=777,reuseaddr" \
            "TCP4:${ip}:${EXT_PORT}"
        local _
        for _ in $(seq 1 25); do [[ -S "$XSOCK" ]] && break; sleep 0.2; done
        [[ -S "$XSOCK" ]] || { echo "[x] socat 转发失败, 见 $LOG/socat.log"; return 1; }
        echo "[+] socat      $XSOCK -> $ip:$EXT_PORT"
    else
        echo "[=] socat      转发已在运行"
    fi

    echo windows > "$MODEFILE"
}

# ---- 状态 ------------------------------------------------------------------
current_backend() {
    [[ -f "$MODEFILE" ]] && cat "$MODEFILE" || echo "未启动"
}

status_stack() {
    local n
    for n in xvfb fluxbox x11vnc noVNC socat; do
        printf "  %-9s " "$n"
        if alive "$n"; then echo "运行中 (pid $(cat "$RUNDIR/$n.pid"))"; else echo "未运行"; fi
    done
    local ip; ip="$(host_ip4)"
    echo
    echo "  当前后端     : $(current_backend)   (DISPLAY=$VDISP)"
    if ext_reachable "$ip"; then
        echo "  Windows X    : 可达 ($EXT_HOST:$EXT_PORT = $ip)"
    else
        echo "  Windows X    : 不可达 ($EXT_HOST:$EXT_PORT = $ip)"
    fi
    echo "  浏览器入口   : http://localhost:$WEB_PORT/vnc.html  (仅 local 后端可用)"
}

# ---- 主流程 ----------------------------------------------------------------
_is_sourced() { [[ "${BASH_SOURCE[0]}" != "${0}" ]]; }
_ret() { _is_sourced && return "$1" || exit "$1"; }

case "${1:-auto}" in
    stop)    stop_local; stop_windows; echo "已全部停止"; _ret 0 ;;
    status)  status_stack; _ret 0 ;;
    check)   ;;
    windows) IP="$(host_ip4)"; start_windows || _ret 1; MODE="Windows 侧 X server (VcXsrv)" ;;
    local)   start_local   || _ret 1; MODE="容器内虚拟显示 (Xvfb)" ;;
    start|auto|"")
             IP="$(host_ip4)"
             # 已经有后端在跑就不切换。切换会先停掉另一套 (Xvfb 与 socat 抢同一个
             # socket 路径), 正在跑的 Gazebo 会跟着挂掉 —— 开个新终端不该有这种
             # 副作用。想换后端就显式敲 windows / local。
             case "$(current_backend)" in
                 windows) if alive socat; then
                              MODE="Windows 侧 X server (VcXsrv)"
                              ext_reachable "$IP" || echo "[!] socat 转发在跑, 但 $EXT_HOST:$EXT_PORT 连不上 —— VcXsrv 是否已关闭?"
                          else
                              if ext_reachable "$IP"; then start_windows || _ret 1; MODE="Windows 侧 X server (VcXsrv)"
                              else start_local || _ret 1; MODE="容器内虚拟显示 (Xvfb)"; fi
                          fi ;;
                 local)   if alive xvfb; then
                              MODE="容器内虚拟显示 (Xvfb)"
                          else
                              if ext_reachable "$IP"; then start_windows || _ret 1; MODE="Windows 侧 X server (VcXsrv)"
                              else start_local || _ret 1; MODE="容器内虚拟显示 (Xvfb)"; fi
                          fi ;;
                 *)       if ext_reachable "$IP"; then start_windows || _ret 1; MODE="Windows 侧 X server (VcXsrv)"
                          else start_local || _ret 1; MODE="容器内虚拟显示 (Xvfb)"; fi ;;
             esac ;;
    *) echo "用法: source /root/display.sh | $0 {start|stop|windows|local|status|check}"; _ret 2 ;;
esac

# DISPLAY 始终是 :0 —— 两个后端都服务于这个号
export DISPLAY="$VDISP"

# 下面两个是"保险"而非"必需": 实测在 Xvfb 存在的前提下, 即使不设这两个变量,
# Mesa 也会自行回退到 llvmpipe 软件渲染 (Gazebo 约 42 FPS)。gzclient 的 exit 134
# 唯一成因就是没有 X server, 与渲染后端无关。显式设上只是避免将来换环境时
# Mesa 误选 GPU 路径。
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
# 走网络到 Windows 的 X server 时 MIT-SHM 不可用, 显式关掉免得客户端报错
export QT_X11_NO_MITSHM=1

if [[ "${1:-auto}" == "check" ]]; then
    echo "  后端        : $(current_backend)"
    echo "  DISPLAY     : $DISPLAY"
    echo "  Windows X   : $EXT_HOST:$EXT_PORT = $(host_ip4)"
    echo
    echo "--- X server 连通性 ---"
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
        echo "  [OK] 连得上 $DISPLAY"
        xdpyinfo -display "$DISPLAY" 2>/dev/null | sed -n 's/^  *\(dimensions\|depth of root\).*/  \1/p' | head -2
    else
        echo "  [x] 连不上 $DISPLAY"
    fi
else
    echo "显示已就绪: $MODE  →  DISPLAY=$DISPLAY"
    case "$(current_backend)" in
        windows) echo "Gazebo 窗口会直接出现在你的 Windows 桌面上" ;;
        local)   echo "浏览器打开: http://localhost:$WEB_PORT/vnc.html" ;;
    esac
fi
