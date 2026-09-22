#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy, math
from nav_msgs.msg import Odometry
from geometry_msgs.msg import Twist


def normalize_angle(a):
    """把角度规约到 [-pi, pi]"""
    while a >  math.pi: a -= 2 * math.pi
    while a < -math.pi: a += 2 * math.pi
    return a


def round_corners(loop, r=0.15, samples=8):
    """把闭合折线的每个拐角替换成半径 r 的圆弧。loop 首点 == 尾点。"""
    pts = list(loop)
    if pts[0] != pts[-1]:
        pts.append(pts[0])

    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, p, b = pts[i - 1], pts[i], pts[i + 1]
        e1 = (p[0] - a[0], p[1] - a[1]); m1 = math.hypot(*e1)
        e2 = (b[0] - p[0], b[1] - p[1]); m2 = math.hypot(*e2)
        if m1 < 1e-9 or m2 < 1e-9:
            out.append(p); continue
        e1 = (e1[0] / m1, e1[1] / m1); e2 = (e2[0] / m2, e2[1] / m2)

        ang = math.acos(max(-1, min(1, e1[0] * e2[0] + e1[1] * e2[1])))  # 转向角
        if ang < 0.08:                       # 接近直线,原样保留顶点
            out.append(p); continue

        d = r / math.tan(ang / 2.0)
        d = min(d, m1 / 2, m2 / 2)           # 切点不超过边长一半
        rr = d * math.tan(ang / 2.0)         # 实际半径

        t1 = (p[0] - e1[0] * d, p[1] - e1[1] * d)  # 上一段边上的切点
        t2 = (p[0] + e2[0] * d, p[1] + e2[1] * d)  # 下一段边上的切点

        bx, by = e1[0] + e2[0], e1[1] + e2[1]      # 角平分线 -> 圆心方向
        bm = math.hypot(bx, by)
        if bm < 1e-9:
            out.append(p); continue
        bx, by = bx / bm, by / bm
        cx = p[0] + bx * (rr / math.sin(ang / 2.0))
        cy = p[1] + by * (rr / math.sin(ang / 2.0))

        a1 = math.atan2(t1[1] - cy, t1[0] - cx)
        a2 = math.atan2(t2[1] - cy, t2[0] - cx)
        delta = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
        for k in range(samples + 1):
            th = a1 + delta * k / samples
            out.append((cx + rr * math.cos(th), cy + rr * math.sin(th)))

    out.append(pts[-1])
    return out


# ---------- 两条巡逻路径(共享起点 (1.13,1.60),各自闭合) ----------
LOOP_A_RAW = [               # 第一条闭环:带切角的路线
    (1.13, 1.55),
    (0.0, 1.60),
    (-1.50, 1.60),
    (-1.60, 0.60),
    (-0.15, 0.50),
    (-0.05, -1.70),
    (1.15, -1.65),
    (1.13, 1.55),
]

LOOP_B_RAW = [               # 第二条闭环:大矩形
    (1.13, 1.55),
    (0.0, 1.60),
    (-1.50, 1.60),
    (-1.55, 1.55),
    (-1.60, 0.0),
    (-1.60, -1.50),
    (-1.55, -1.70),
    (0.0, -1.75),
    (1.05, -1.75),
    (1.13, 0.0),
    (1.13, 1.55),
]

LOOPS = [
    round_corners(LOOP_A_RAW, r=0.15, samples=8),
    round_corners(LOOP_B_RAW, r=0.15, samples=8),
]

current_idx = 0
current_loop = LOOPS[current_idx]

# 完成一圈的判定:先离开起点 DEPART_DIST,再回到起点 RETURN_DIST 内算一圈
DEPART_DIST = 0.5    # 离开起点多远算"已出发"
RETURN_DIST = 0.35   # 回到起点多近算"完成一圈"

# ---------- 调参区 ----------
LOOKAHEAD  = 0.3    # 前瞻距离,越大越早发现弯、越早减速、拐弯越圆润
MAX_V      = 0.25   # 最大线速度
MAX_W      = 1.5    # 最大角速度(滑移底盘建议别超过 1.0,否则易打滑)
SLOW_DEPTH = 0.3    # 急弯减速幅度:直角弯降到 MAX_V 的 (1-0.3)

px = py = pyaw = 0.0
have_odom = False
started = False      # 是否已离开起点(避免开局就误判"完成一圈")


def odom_cb(m):
    global px, py, pyaw, have_odom
    px = m.pose.pose.position.x
    py = m.pose.pose.position.y
    q  = m.pose.pose.orientation
    pyaw = math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
    have_odom = True


def point_ahead(loop, x, y, L):
    """返回 (gx, gy, turn)。gx,gy 是路径上机器人前方 L 米的目标点,
    turn 是这 L 米内路径的累计转向弧度(用于前瞻减速)。"""
    best_s, best_t, best_d = 0, 0.0, float('inf')
    for s in range(len(loop) - 1):
        x1, y1 = loop[s]; x2, y2 = loop[s + 1]
        dx, dy = x2 - x1, y2 - y1
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / L2))
        cx, cy = x1 + t * dx, y1 + t * dy
        d = (cx - x) ** 2 + (cy - y) ** 2
        if d < best_d:
            best_d, best_s, best_t = d, s, t

    s, t = best_s, best_t
    x1, y1 = loop[s]; x2, y2 = loop[s + 1]
    prev_dir = math.atan2(y2 - y1, x2 - x1)
    turn = 0.0
    remaining = L
    for _ in range(len(loop)):
        seg_len = math.hypot(x2 - x1, y2 - y1)
        to_end  = (1.0 - t) * seg_len
        if remaining <= to_end:
            frac = (t * seg_len + remaining) / seg_len
            gx = x1 + frac * (x2 - x1)
            gy = y1 + frac * (y2 - y1)
            dir_now = math.atan2(y2 - y1, x2 - x1)
            turn += normalize_angle(dir_now - prev_dir)
            return gx, gy, abs(turn)
        remaining -= to_end
        s = (s + 1) % (len(loop) - 1)
        t = 0.0
        x1, y1 = loop[s]; x2, y2 = loop[s + 1]
        dir_now = math.atan2(y2 - y1, x2 - x1)
        turn += normalize_angle(dir_now - prev_dir)
        prev_dir = dir_now
    return x1, y1, abs(turn)


if __name__ == '__main__':
    rospy.init_node('patrol')
    rospy.Subscriber('/odom', Odometry, odom_cb)
    pub = rospy.Publisher('/cmd_vel', Twist, queue_size=1)
    rate = rospy.Rate(20)

    while not rospy.is_shutdown():
        if not have_odom:
            rate.sleep(); continue

        # ---- 完成一圈判定:离开起点后再回到起点附近 -> 切换下一条 ----
        sx, sy = current_loop[0]
        d_start = math.hypot(px - sx, py - sy)
        if not started and d_start > DEPART_DIST:
            started = True
        elif started and d_start < RETURN_DIST:
            current_idx = (current_idx + 1) % len(LOOPS)
            current_loop = LOOPS[current_idx]
            started = False
            rospy.loginfo("完成一圈,切换到第 %d 条路径", current_idx + 1)

        gx, gy, turn = point_ahead(current_loop, px, py, LOOKAHEAD)

        # 转到机器人坐标系
        dx, dy = gx - px, gy - py
        local_x =  math.cos(pyaw) * dx + math.sin(pyaw) * dy
        local_y = -math.sin(pyaw) * dx + math.cos(pyaw) * dy
        alpha = math.atan2(local_y, local_x)

        # ① 曲率前瞻减速
        curv   = min(1.0, turn / (math.pi / 2.0))
        v_turn = MAX_V * (1.0 - SLOW_DEPTH * curv)

        # ② 方向对齐衰减(给滑移底盘留最低速,别原地磨)
        v = v_turn * max(0.3, math.cos(alpha))

        w = 2.0 * v * math.sin(alpha) / LOOKAHEAD
        w = max(-MAX_W, min(MAX_W, w))

        cmd = Twist()
        cmd.linear.x = v
        cmd.angular.z = w
        pub.publish(cmd)
        rate.sleep()
