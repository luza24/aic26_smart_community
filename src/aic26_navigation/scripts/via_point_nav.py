#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy, math
import actionlib
from nav_msgs.msg import Path
from geometry_msgs.msg import PoseStamped
from move_base_msgs.msg import MoveBaseAction, MoveBaseGoal

# 你的航点(和之前一致,闭合一圈)
WAYPOINTS = [
    (1.13, 1.60),
    (0.0,  1.60),
    (-1.63, 1.60),
    (-1.63, 0.0),
    (-1.63, -1.63),
    (0.0,  -1.63),
    (1.13, -1.63),
    (1.13, 0.0),
    (1.13, 1.50),
]

def make_path(waypoints, step=0.05):
    """把稀疏航点插值成稠密 Path,每 step 米一个点"""
    path = Path()
    path.header.frame_id = "map"
    path.header.stamp = rospy.Time.now()

    for i in range(len(waypoints) - 1):
        x1, y1 = waypoints[i]
        x2, y2 = waypoints[i + 1]
        dist = math.hypot(x2 - x1, y2 - y1)
        n = max(1, int(dist / step))
        for k in range(n):                      # 不加最后一个点,避免和下段重复
            t = k / float(n)
            p = PoseStamped()
            p.header.frame_id = "map"
            p.pose.position.x = x1 + (x2 - x1) * t
            p.pose.position.y = y1 + (y2 - y1) * t
            p.pose.orientation.w = 1.0          # 朝向不管,overwrite 会忽略
            path.poses.append(p)

    # 补上最后一个终点
    last = PoseStamped()
    last.header.frame_id = "map"
    last.pose.position.x = waypoints[-1][0]
    last.pose.position.y = waypoints[-1][1]
    last.pose.orientation.w = 1.0
    path.poses.append(last)

    path.header.stamp = rospy.Time.now()
    return path

if __name__ == '__main__':
    rospy.init_node('via_point_nav')
    client = actionlib.SimpleActionClient('move_base', MoveBaseAction)
    rospy.loginfo("waiting for move_base...")
    client.wait_for_server()
    rospy.loginfo("move_base up")

    # ★ TEB 订阅的 global_plan 话题,先按这个发,不对再改(见第 5 步)
    plan_pub = rospy.Publisher(
        '/move_base/TebLocalPlannerROS/global_plan', Path, queue_size=1)

    # 1) 发 goal 到最后一个航点,只用来激活 move_base
    goal = MoveBaseGoal()
    goal.target_pose.header.frame_id = "map"
    goal.target_pose.header.stamp = rospy.Time.now()
    goal.target_pose.pose.position.x = WAYPOINTS[-1][0]
    goal.target_pose.pose.position.y = WAYPOINTS[-1][1]
    goal.target_pose.pose.orientation.w = 1.0
    client.send_goal(goal)

    # 2) 高频覆盖 global_plan,让 TEB 一直沿我们的路点走
    path = make_path(WAYPOINTS)
    rate = rospy.Rate(5)                        # 5 Hz 刷新
    while not rospy.is_shutdown():
        path.header.stamp = rospy.Time.now()
        plan_pub.publish(path)
        rate.sleep()

