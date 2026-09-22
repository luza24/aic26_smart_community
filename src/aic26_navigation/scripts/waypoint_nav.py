#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy
import math
import actionlib
from move_base_msgs.msg import MoveBaseAction, MoveBaseGoal

def go(client, x, y, yaw):
    goal = MoveBaseGoal()
    goal.target_pose.header.frame_id = "map"
    goal.target_pose.header.stamp = rospy.Time.now()
    goal.target_pose.pose.position.x = x
    goal.target_pose.pose.position.y = y
    goal.target_pose.pose.orientation.z = math.sin(yaw / 2.0)
    goal.target_pose.pose.orientation.w = math.cos(yaw / 2.0)
    client.send_goal(goal)
    # 最多等 20 秒，超时就不等了（防止卡死）
    client.wait_for_result(rospy.Duration(8))
    return client.get_state()

if __name__ == '__main__':
    rospy.init_node('waypoint_nav')
    client = actionlib.SimpleActionClient('move_base', MoveBaseAction)
    rospy.loginfo("waiting for move_base...")
    client.wait_for_server()

    # TODO: 把你在 RViz 里点的坐标填到这里
    '''waypoints = [
        (1.703, 1.678),
        (-1.59, 1.59),
        (-1.59, -1.71),
        (-0.164,-1.71),
        (-0.164,0.36),
        (-1.63,0.417),
        (-1.59,-1.61),
        (1.02,-1.60),
        (1.07,1.66)
        # ... 继续填
    ]'''
    waypoints = [
      (1.13, 1.60),    # NE 起点
      (0.0, 1.60),     # 北边中点
      
      (-1.63, 1.60),   # NW 角
      (-1.63,1.00),
      (-1.63, 0.0),    # 西边中点
      (-1.60, -1.60),  # SW 角
      (0.0, -1.60),    # 南边中点
      (1.13, -1.60),   # SE 角
      (1.13, 0.0),     # 东边中点
      (1.13, 1.60),    # 回到 NE（闭合）    
  ]

    for i, (x, y) in enumerate(waypoints):
        if i < len(waypoints) - 1:
            nx, ny = waypoints[i + 1]
            yaw = math.atan2(ny - y, nx - x)
        else:
            yaw = 0.0

        rospy.loginfo("going to (%f, %f)", x, y)
        state = go(client, x, y, yaw)
        if state == actionlib.GoalStatus.SUCCEEDED:
            rospy.loginfo("reached!")
        else:
            rospy.logwarn("point (%f,%f) failed/aborted, state=%d", x, y, state)
        rospy.sleep(0.05)