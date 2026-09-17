#!/usr/bin/env bash
# =============================================================================
#  容器内图形显示配置 —— 让 Gazebo GUI / RViz 能正常渲染
#
#  背景: 容器里 DISPLAY=:0, 但 :0 背后不一定有 X server。没有的话 gzclient 会在
#        创建 GL context 时 abort (exit code 134 / SIGABRT)。
#
#  三种后端, 都服务于 :0 —— 所以 DISPLAY=:0 在三种模式下都天然正确, 不依赖任何
#  shell 配置:
#
#    external  平台/环境已经给 :0 备好了一个能用的 X server, 本脚本**什么都不启动**,
#              直接复用。实测: Docker Desktop 会把 VM 的 /.X11-unix 只读挂进容器的
#              /tmp/.X11-unix, 里面那个 X0 就是它 —— 窗口直接出现在 Windows 桌面。
#              这种环境**优先选它**: 硬起 Xvfb 只会 fatal ("Make sure an X server
#              isn't already running"), fluxbox / x11vnc 也全都活不下来。
#
#    windows   没有现成的可用, 才用 socat 把容器内的 :0 转发到 Windows 侧 X server
#              (VcXsrv, host.docker.internal:6000)。画面在 Windows 桌面。
#
#    local     Xvfb 在容器内起一块虚拟屏幕, 画面用浏览器看 (noVNC, :6080)。
#
#  选后端的顺序永远是 external > windows > local: 能用现成的就不自己造。
#
#  用法:
#      source /root/display.sh          # 自动选后端
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

XDpyInfo="$(command -v xdpyinfo 2>/dev/null)"

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

# $VDISP 上是否真的有一个**连得上**的 X server。
#
# 绝不能拿 `[[ -S "$XSOCK" ]]` 代替 —— 那只问"socket 文件在不在"。Docker Desktop
# 常驻挂进来的 X0 会让它永远为真, 于是 Xvfb 明明已经 fatal 退出, 脚本还是打印
# "[+] Xvfb 启动成功" 并接着去起 fluxbox / x11vnc, 两个进程秒退 —— 用户就在交互
# shell 里看到一串 `[2]- Exit 1 setsid bash -c ...` 的作业通知。这就是"看文件在不在"
# 这个判据的全部代价。
x_alive() {
    if [[ -n "$XDpyInfo" ]]; then
        "$XDpyInfo" -display "$VDISP" >/dev/null 2>&1
    else
        [[ -S "$XSOCK" ]]       # 没有 xdpyinfo 只能退化成看文件, 会假阳性, 但聊胜于无
    fi
}

# 等 $VDISP 变得不可连。X server / socat 收到 SIGTERM 后不会瞬间退净, 不等就判会
# 拿到"还活着"的旧结论, 后面 socat 与 Xvfb 会互相抢 socket。
wait_x_down() {
    local i
    for i in $(seq 1 25); do x_alive || return 0; sleep 0.2; done
    return 1
}

# 读进程启动时刻 (内核 jiffies, /proc/<pid>/stat 第 22 字段)。
# 先剥掉 "(comm) " 再数第 20 列 —— comm 里可能有空格, 直接 awk '{print $22}' 会错位。
proc_starttime() {
    sed 's/^[^)]*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f20
}

# 某个进程是否还活着 (读 pidfile)。
# 光 kill -0 不够: 进程死后内核会把 PID 复用给别人, kill -0 就假阳性 —— 而
# stop / 后端切换拿这个号去 kill 就是误杀一个不相干的进程。pidfile 第二个字段
# 记的是启动时刻, 对得上才算"还是它"。
alive() {
    local f="$RUNDIR/$1.pid" pid st
    [[ -f "$f" ]] || return 1
    read -r pid st < "$f" || return 1
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ -z "$st" ]] && return 0          # 旧格式 pidfile(只有 PID): 只能按"活着"判
    [[ "$(proc_starttime "$pid")" == "$st" ]]
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
    # pidfile 写 "PID 启动时刻" 两个字段, 后者用于识别 PID 复用 (见 alive)。
    setsid bash -c '
        p=$$
        st=$(sed "s/^[^)]*) //" "/proc/$p/stat" | cut -d" " -f20)
        echo "$p $st" > "$1"
        shift
        exec "$@"
    ' bash "$RUNDIR/$name.pid" "$@" >>"$LOG/$name.log" 2>&1 &
    local i
    for i in $(seq 1 25); do [[ -s "$RUNDIR/$name.pid" ]] && return 0; sleep 0.2; done
    return 0
}

kill_component() {
    local n="$1"
    if alive "$n"; then
        kill "$(cut -d' ' -f1 "$RUNDIR/$n.pid")" 2>/dev/null
        echo "[-] 已停止 $n"
    fi
    rm -f "$RUNDIR/$n.pid"
}

# ---- 谁在服务 $VDISP -------------------------------------------------------
# X0 是不是"本脚本建、本脚本在服务的"? 只有这种才允许删。
# 判据: 有活着的自家组件 且 socket 所在目录可写 —— 平台挂进来的 /.X11-unix 是
# 只读 tmpfs, 一票否决。
xsock_is_ours() {
    [[ -w "$(dirname "$XSOCK")" ]] || return 1
    alive xvfb || alive socat
}

# $VDISP 上有一个"能用、且不是本脚本起的" X server —— 直接复用它, 不要抢。
external_in_use() {
    x_alive || return 1
    xsock_is_ours && return 1
    return 0
}

# 删掉 $VDISP 的 socket。只在"确定是自己建的、而且已经没人在用"时才动手。
# 只读挂载上那个 socket 是别人活着的 server 的地址 —— 删了 = 所有正在跑的
# Gazebo / RViz 一起掉线。
drop_our_socket() {
    [[ -e "$XSOCK" ]] || return 0
    if [[ ! -w "$(dirname "$XSOCK")" ]]; then
        echo "[!] $XSOCK 在只读挂载上 (平台挂进来的), 保留不动"
        return 0
    fi
    if x_alive; then
        echo "[!] $VDISP 上仍有一个活着的 X server 在用 $XSOCK, 保留不动"
        return 0
    fi
    rm -f "$XSOCK"
}

# 把"现在实际在服务 $VDISP 的是谁"记到 MODEFILE —— status / 模式切换靠它判断。
# 谁都没在服务时把它删掉: 留着上一次的值会让 status 报一个早就不成立的后端。
sync_modefile() {
    if   external_in_use; then echo external > "$MODEFILE"
    elif alive xvfb;      then echo local    > "$MODEFILE"
    elif alive socat;     then echo windows  > "$MODEFILE"
    else                       rm -f "$MODEFILE"
    fi
}

# $VDISP 当前状态的一句话描述
x_state() {
    if ! x_alive; then
        echo "连不上 (没有可用的 X server)"
    elif xsock_is_ours; then
        echo "可用 (本脚本的 $(current_backend) 后端在服务)"
    else
        echo "可用 (平台/环境自带, 非本脚本启动)"
    fi
}

# ---- local 后端:容器内 Xvfb ------------------------------------------------
stop_local() {
    local n
    for n in noVNC x11vnc fluxbox xvfb; do kill_component "$n"; done
}

start_local() {
    mkdir -p "$LOG"

    # 平台已经给了能用的 $VDISP —— 再起一个 Xvfb 只会
    #   (EE) Cannot establish any listening sockets - Make sure an X server isn't already running
    # 而"看 socket 文件在不在"的老判据还会把这个失败当成成功。这里直接说清楚。
    if external_in_use; then
        echo "[x] $VDISP 上是平台提供的 X server (非本脚本启动), 无法再起 Xvfb ——"
        echo "    起也起不来: 它会 fatal 在 'Cannot establish any listening sockets'。"
        echo "    直接用它就好 (窗口已经在 Windows 桌面上)。确实要用容器内虚拟显示,"
        echo "    得先在平台上把 $VDISP 让出来。"
        return 1
    fi

    # 只读挂载时 Xvfb 连 socket 都建不出来, 与其让它去撞, 不如在这里就说清楚
    if [[ ! -w "$(dirname "$XSOCK")" ]]; then
        echo "[x] $(dirname "$XSOCK") 是只读挂载, 容器没法在这里建自己的 X socket ——"
        echo "    Xvfb 起不来, socat 转发一样起不来。这个挂载是平台给的, 只能由平台那边"
        echo "    把 $VDISP 重新递进来(或者换成可写挂载重启)。"
        return 1
    fi

    # 先停掉 windows 后端的转发 —— 否则切回来时 socat 残留, 还占着 X0 socket
    stop_windows

    # 1. Xvfb —— 虚拟显示本体
    if ! alive xvfb; then
        if [[ -z "$(command -v Xvfb)" ]]; then
            echo "[x] 缺少 Xvfb, 请先: bash docker/setup.sh"
            return 1
        fi
        drop_our_socket     # 上一轮可能留下死 socket, Xvfb 会因为绑不上而拒绝启动
        spawn xvfb Xvfb "$VDISP" -screen 0 "$GEOMETRY" -ac +extension GLX +render -noreset
        local i
        for i in $(seq 1 30); do x_alive && break; sleep 0.2; done
        if ! x_alive; then
            echo "[x] Xvfb 启动失败, 见 $LOG/xvfb.log"
            tail -n 4 "$LOG/xvfb.log" 2>/dev/null | sed 's/^/    /'
            return 1
        fi
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

# ---- windows 后端:socat 转发到 VcXsrv --------------------------------------
stop_windows() {
    local had=0
    alive socat && had=1
    kill_component socat
    # 只有"socat 确实是本脚本起的"才考虑删 socket —— 见 drop_our_socket
    [[ $had -eq 1 ]] && drop_our_socket
    return 0
}

start_windows() {
    mkdir -p "$LOG"
    local ip; ip="$(host_ip4)"

    # 平台已经给了能用的 $VDISP 时, socat 没有槽位可占, 抢过来只会把别人的显示弄挂
    if external_in_use; then
        echo "[x] $VDISP 上是平台提供的 X server (非本脚本启动), 无需也不该用 socat 转发"
        return 1
    fi

    # 只读挂载上 socat 也绑不了 socket, 提前说清楚, 别让它去撞一个必然的失败
    if [[ ! -w "$(dirname "$XSOCK")" ]]; then
        echo "[x] $(dirname "$XSOCK") 是只读挂载, socat 无法在这里建 socket"
        return 1
    fi

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
    wait_x_down || { echo "[x] 旧的 X server 还没退干净, $VDISP 一直连得上"; return 1; }
    drop_our_socket

    if ! alive socat; then
        spawn socat socat \
            "UNIX-LISTEN:${XSOCK},fork,mode=777,reuseaddr" \
            "TCP4:${ip}:${EXT_PORT}"
        local i
        for i in $(seq 1 25); do x_alive && break; sleep 0.2; done
        if ! x_alive; then
            echo "[x] socat 转发失败, 见 $LOG/socat.log"
            tail -n 4 "$LOG/socat.log" 2>/dev/null | sed 's/^/    /'
            return 1
        fi
        echo "[+] socat      $XSOCK -> $ip:$EXT_PORT"
    else
        echo "[=] socat      转发已在运行"
        x_alive || echo "[!] 但 $VDISP 连不上 —— Windows 侧 VcXsrv 是否已关闭?"
    fi
}

# ---- 状态 ------------------------------------------------------------------
current_backend() {
    [[ -f "$MODEFILE" ]] && cat "$MODEFILE" || echo "未启动"
}

status_stack() {
    local n
    sync_modefile       # 先把"实际是谁在服务"落盘, 免得下面报一个早就不成立的后端
    for n in xvfb fluxbox x11vnc noVNC socat; do
        printf "  %-9s " "$n"
        if alive "$n"; then
            echo "运行中 (pid $(cut -d' ' -f1 "$RUNDIR/$n.pid"))"
        else
            echo "未运行"
        fi
    done
    local ip; ip="$(host_ip4)"
    echo
    echo "  $VDISP           : $(x_state)"
    echo "  当前后端     : $(current_backend)"
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

# 按优先级挑后端: 平台自带 > Windows 侧 X server > 容器内 Xvfb
pick_backend() {
    local ip="$1"
    if external_in_use; then
        MODE="平台/环境提供的 X server ($VDISP)"
    elif ext_reachable "$ip"; then
        start_windows || return 1
        MODE="Windows 侧 X server (VcXsrv)"
    else
        start_local || return 1
        MODE="容器内虚拟显示 (Xvfb)"
    fi
}

case "${1:-auto}" in
    stop)    stop_local; stop_windows; rm -f "$MODEFILE"; echo "已全部停止"; _ret 0 ;;
    status)  status_stack; _ret 0 ;;
    check)   ;;
    windows) start_windows || _ret 1; MODE="Windows 侧 X server (VcXsrv)"; sync_modefile ;;
    local)   start_local   || _ret 1; MODE="容器内虚拟显示 (Xvfb)";       sync_modefile ;;
    start|auto|"")
             IP="$(host_ip4)"
             # 已经有后端在跑就不切换。切换会先停掉另一套 (Xvfb 与 socat 抢同一个
             # socket 路径), 正在跑的 Gazebo 会跟着挂掉 —— 开个新终端不该有这种
             # 副作用。想换后端就显式敲 windows / local。
             case "$(current_backend)" in
                 external) if external_in_use; then
                               MODE="平台/环境提供的 X server ($VDISP)"
                           else
                               pick_backend "$IP" || _ret 1
                           fi ;;
                 local)    if alive xvfb; then
                               MODE="容器内虚拟显示 (Xvfb)"
                           else
                               pick_backend "$IP" || _ret 1
                           fi ;;
                 windows)  if alive socat; then
                               MODE="Windows 侧 X server (VcXsrv)"
                               ext_reachable "$IP" || echo "[!] socat 转发在跑, 但 $EXT_HOST:$EXT_PORT 连不上 —— VcXsrv 是否已关闭?"
                           else
                               pick_backend "$IP" || _ret 1
                           fi ;;
                 *)        pick_backend "$IP" || _ret 1 ;;
             esac
             sync_modefile ;;
    *) echo "用法: source /root/display.sh | $0 {start|stop|windows|local|status|check}"; _ret 2 ;;
esac

# DISPLAY 始终是 :0 —— 三个后端都服务于这个号
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
    echo "  $VDISP          : $(x_state)"
    echo "  DISPLAY     : $DISPLAY"
    echo "  Windows X   : $EXT_HOST:$EXT_PORT = $(host_ip4)"
    echo
    echo "--- 环境 ---"
    for _t in xdpyinfo Xvfb x11vnc fluxbox socat websockify; do
        printf "  %-11s %s\n" "$_t" "$(command -v "$_t" || echo '缺失 —— bash docker/setup.sh')"
    done
    echo "  $XSOCK 所在挂载: $(findmnt -no FSTYPE,OPTIONS --target "$XSOCK" 2>/dev/null || echo '不存在')"
    echo
    echo "--- X server 连通性 ---"
    if x_alive; then
        echo "  [OK] 连得上 $DISPLAY"
        if [[ -n "$XDpyInfo" ]]; then
            "$XDpyInfo" -display "$DISPLAY" 2>/dev/null |
                grep -E '^ *(dimensions|depth of root window):' | sed 's/^ */    /'
        fi
    else
        echo "  [x] 连不上 $DISPLAY"
    fi
else
    echo "显示已就绪: $MODE  →  DISPLAY=$DISPLAY"
    case "$(current_backend)" in
        external) echo "窗口由平台/环境提供的 X server 渲染 (实测: 直接出现在 Windows 桌面)" ;;
        windows)  echo "Gazebo 窗口会直接出现在你的 Windows 桌面上" ;;
        local)    echo "浏览器打开: http://localhost:$WEB_PORT/vnc.html" ;;
    esac
fi
