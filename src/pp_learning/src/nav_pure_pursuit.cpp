#include <ros/ros.h>
#include <geometry_msgs/Twist.h>
#include <geometry_msgs/Pose2D.h>
#include <geometry_msgs/PoseStamped.h>
#include <nav_msgs/Odometry.h>
#include <nav_msgs/Path.h>
#include <sensor_msgs/LaserScan.h>
#include <tf/transform_datatypes.h>
#include <cmath>
#include <vector>
#include <algorithm>
#include <geometry_msgs/PoseWithCovarianceStamped.h>

class IntegratedNavigator
{
public:
    IntegratedNavigator()
    {
        cmd_pub_ = nh_.advertise<geometry_msgs::Twist>("/cmd_vel", 10);
        odom_sub_ = nh_.subscribe("/amcl_pose", 1, &IntegratedNavigator::amclPoseCallback, this);
        path_sub_ = nh_.subscribe("/move_base/NavfnROS/plan", 1, &IntegratedNavigator::pathCallback, this);
        scan_sub_ = nh_.subscribe("/scan", 1, &IntegratedNavigator::scanCallback, this);

        lookahead_distance_ = 0.8;
        max_linear_vel_ = 0.4;
        min_linear_vel_ = 0.05;
        max_angular_vel_ = 1.5;
        safety_distance_ = 0.5;
        emergency_distance_ = 0.25;
        turn_force_ = 1.2;
        max_curvature_ = 3.0;   // 新增：曲率限幅

        has_odom_ = false;
        has_path_ = false;
        obstacle_detected_ = false;
        left_clearance_ = 999.0;
        right_clearance_ = 999.0;
        front_clearance_ = 999.0;

        ROS_INFO("Integrated Navigator (PurePursuit + Local Obstacle Avoidance) Started.");
    }

    void amclPoseCallback(const geometry_msgs::PoseWithCovarianceStamped::ConstPtr& msg)
    {
        robot_pose_.x = msg->pose.pose.position.x;
        robot_pose_.y = msg->pose.pose.position.y;
        robot_pose_.theta = tf::getYaw(msg->pose.pose.orientation);
        has_odom_ = true;
    }

    void pathCallback(const nav_msgs::Path::ConstPtr& msg)
    {
        if (msg->poses.empty()) {
            has_path_ = false;
            return;
        }
        // 检查路径首点是否距离机器人太远（防止规划异常）
        geometry_msgs::Pose2D first;
        first.x = msg->poses[0].pose.position.x;
        first.y = msg->poses[0].pose.position.y;
        double dist = distance2D(robot_pose_, first);
        if (dist > 10.0) {
            ROS_WARN("Path first point too far (%.2f m), ignoring.", dist);
            has_path_ = false;
            return;
        }
        path_ = *msg;
        has_path_ = true;
        ROS_INFO("Path received: %lu waypoints.", path_.poses.size());
    }

    void scanCallback(const sensor_msgs::LaserScan::ConstPtr& scan)
    {
        left_clearance_ = scan->range_max;
        right_clearance_ = scan->range_max;
        front_clearance_ = scan->range_max;

        int num_ranges = scan->ranges.size();
        for (int i = 0; i < num_ranges; i++) {
            if (scan->ranges[i] < scan->range_min || scan->ranges[i] > scan->range_max)
                continue;

            double angle = scan->angle_min + i * scan->angle_increment;
            double dist = scan->ranges[i];

            if (angle < -0.5 && angle > -1.57) {
                left_clearance_ = std::min(left_clearance_, dist);
            } 
            else if (angle > 0.5 && angle < 1.57) {
                right_clearance_ = std::min(right_clearance_, dist);
            } 
            else if (std::abs(angle) <= 0.5) {
                front_clearance_ = std::min(front_clearance_, dist);
            }
        }

        if (front_clearance_ < safety_distance_ || left_clearance_ < safety_distance_ * 0.6 || right_clearance_ < safety_distance_ * 0.6) {
            obstacle_detected_ = true;
        } else {
            obstacle_detected_ = false;
        }
    }

    void run()
    {
       if (!has_odom_) {
            ROS_WARN_THROTTLE(1, "Waiting for amcl_pose...");
            return;
        }
        if (!has_path_) {
            ROS_WARN_THROTTLE(1, "Waiting for path...");
            return;
        }

        geometry_msgs::Twist cmd = computePurePursuit();

        if (obstacle_detected_) {
            applyObstacleAvoidance(cmd);
        }

        cmd.linear.x = std::max(0.0, std::min(max_linear_vel_, cmd.linear.x));
        cmd.angular.z = std::max(-max_angular_vel_, std::min(max_angular_vel_, cmd.angular.z));

        cmd_pub_.publish(cmd);
    }

private:
    double distance2D(const geometry_msgs::Pose2D& p1, const geometry_msgs::Pose2D& p2) {
        return std::sqrt(std::pow(p1.x-p2.x,2) + std::pow(p1.y-p2.y,2));
    }

    void transformToRobot(const geometry_msgs::Pose2D& global, double& lx, double& ly) {
        double dx = global.x - robot_pose_.x;
        double dy = global.y - robot_pose_.y;
        double c = std::cos(robot_pose_.theta);
        double s = std::sin(robot_pose_.theta);
        lx = dx * c + dy * s;
        ly = -dx * s + dy * c;
    }

    geometry_msgs::Pose2D findLookahead() {
        if (path_.poses.empty()) {
            geometry_msgs::Pose2D last;
            last.x = robot_pose_.x;
            last.y = robot_pose_.y;
            last.theta = 0;
            return last;
        }

        if (path_.poses.size() < 2) {
            geometry_msgs::Pose2D last;
            last.x = path_.poses.back().pose.position.x;
            last.y = path_.poses.back().pose.position.y;
            last.theta = 0;
            return last;
        }

        for (size_t i=0; i<path_.poses.size()-1; i++) {
            const auto& p1 = path_.poses[i].pose.position;
            const auto& p2 = path_.poses[i+1].pose.position;

            geometry_msgs::Pose2D p1_2d, p2_2d;
            p1_2d.x = p1.x; p1_2d.y = p1.y; p1_2d.theta = 0;
            p2_2d.x = p2.x; p2_2d.y = p2.y; p2_2d.theta = 0;

            double d1 = distance2D(robot_pose_, p1_2d);
            double d2 = distance2D(robot_pose_, p2_2d);

            if (d1 <= lookahead_distance_ && d2 >= lookahead_distance_) {
                double ratio = (lookahead_distance_ - d1) / (d2 - d1 + 0.0001);
                geometry_msgs::Pose2D target;
                target.x = p1.x + ratio * (p2.x - p1.x);
                target.y = p1.y + ratio * (p2.y - p1.y);
                target.theta = 0;

                // ★ 检查目标点是否在机器人前方
                double lx, ly;
                transformToRobot(target, lx, ly);
                if (lx > 0.2) {  // 前方且有足够距离
                    return target;
                } else {
                    // 若在后方或太近，继续向后搜索
                    continue;
                }
            }
        }

        // 未找到有效前瞻点，返回路径终点（但会检查终点是否在前方）
        geometry_msgs::Pose2D last;
        last.x = path_.poses.back().pose.position.x;
        last.y = path_.poses.back().pose.position.y;
        last.theta = 0;
        return last;
    }

    geometry_msgs::Twist computePurePursuit() {
        geometry_msgs::Twist cmd;
        cmd.linear.x = 0;
        cmd.angular.z = 0;

        geometry_msgs::Pose2D target = findLookahead();
        double local_x, local_y;
        transformToRobot(target, local_x, local_y);

        if (local_x < 0.2) {
        
    // 目标在后方，原地旋转（角速度固定，线速度为0）
        cmd.linear.x = 0.0;
        cmd.angular.z = 0.5;  // 正值为向左转，可根据需要调整
        ROS_WARN_THROTTLE(1, "Target behind, turning in place...");
        return cmd;

        }

        double curvature = 0.0;
        double dist_sq = local_x*local_x + local_y*local_y;
        if (dist_sq > 0.001) {
            curvature = (2.0 * local_y) / dist_sq;
        }

        // ★ 限幅曲率，防止角速度过大
        if (curvature > max_curvature_) curvature = max_curvature_;
        else if (curvature < -max_curvature_) curvature = -max_curvature_;

        double linear = max_linear_vel_;
        double abs_curv = std::abs(curvature);
        if (abs_curv > 0.5) {
            linear = max_linear_vel_ * (1.0 / (1.0 + abs_curv));
        }

        // 终点减速
        geometry_msgs::Pose2D goal_pose;
        goal_pose.x = path_.poses.back().pose.position.x;
        goal_pose.y = path_.poses.back().pose.position.y;
        goal_pose.theta = 0;
        double dist_goal = distance2D(robot_pose_, goal_pose);
        if (dist_goal < lookahead_distance_) {
            linear = linear * (dist_goal / lookahead_distance_);
        }
        if (linear < 0.01) linear = 0.0;

        double angular = linear * curvature;
        cmd.linear.x = linear;
        cmd.angular.z = angular;
        return cmd;
    }

    void applyObstacleAvoidance(geometry_msgs::Twist& cmd) {
        if (front_clearance_ < emergency_distance_) {
            cmd.linear.x = 0.0;
            if (std::abs(cmd.angular.z) < 0.3) {
                if (left_clearance_ > right_clearance_) cmd.angular.z = max_angular_vel_ * 0.8;
                else cmd.angular.z = -max_angular_vel_ * 0.8;
            }
            ROS_WARN_THROTTLE(1, "Emergency Stop! Front: %.2f", front_clearance_);
            return;
        }

        if (front_clearance_ < safety_distance_) {
            double scale = (front_clearance_ / safety_distance_);
            cmd.linear.x = cmd.linear.x * std::min(1.0, scale * 0.8 + 0.2);

            double left_gap = left_clearance_;
            double right_gap = right_clearance_;
            
            if (left_gap > right_gap) {
                cmd.angular.z = turn_force_ * 0.6;
            } else {
                cmd.angular.z = -turn_force_ * 0.6;
            }
            if (std::abs(cmd.angular.z) < 0.3) {
                cmd.angular.z = (left_gap > right_gap) ? 0.5 : -0.5;
            }
            ROS_DEBUG("Avoiding: front=%.2f, turn=%.2f", front_clearance_, cmd.angular.z);
        }
        
        if (left_clearance_ < safety_distance_ * 0.5) {
            cmd.angular.z = -0.5;
            cmd.linear.x = cmd.linear.x * 0.8;
        } else if (right_clearance_ < safety_distance_ * 0.5) {
            cmd.angular.z = 0.5;
            cmd.linear.x = cmd.linear.x * 0.8;
        }
    }

    ros::NodeHandle nh_;
    ros::Publisher cmd_pub_;
    ros::Subscriber odom_sub_, path_sub_, scan_sub_;
    ros::Subscriber goal_sub_;  // 保留但未使用

    nav_msgs::Path path_;
    geometry_msgs::Pose2D robot_pose_;
    double current_speed_ = 0.0;
    bool has_odom_ = false, has_path_ = false;

    double lookahead_distance_, max_linear_vel_, min_linear_vel_, max_angular_vel_;
    double safety_distance_, emergency_distance_, turn_force_;
    double max_curvature_;  // 新增

    bool obstacle_detected_ = false;
    double front_clearance_, left_clearance_, right_clearance_;
};

int main(int argc, char** argv)
{
    ros::init(argc, argv, "integrated_navigator");
    IntegratedNavigator nav;
    ros::Rate rate(20);
    while (ros::ok()) {
        ros::spinOnce();
        nav.run();
        rate.sleep();
    }
    return 0;
}