#include <ros/ros.h>
#include <geometry_msgs/Twist.h>
#include <geometry_msgs/Pose2D.h>
#include <geometry_msgs/PoseStamped.h>
#include <nav_msgs/Odometry.h>
#include <nav_msgs/Path.h>
#include <tf/transform_datatypes.h>
#include <cmath>
#include <vector>

class SimplePurePursuit
{
public:
    SimplePurePursuit()
    {
        cmd_pub_ = nh_.advertise<geometry_msgs::Twist>("/cmd_vel", 10);
        odom_sub_ = nh_.subscribe("/odom", 1, &SimplePurePursuit::odomCallback, this);
        path_sub_ = nh_.subscribe("/path", 1, &SimplePurePursuit::pathCallback, this);
        // 新增：订阅 Rviz 的 2D Nav Goal
        goal_sub_ = nh_.subscribe("/move_base_simple/goal", 1, &SimplePurePursuit::goalCallback, this);

        lookahead_distance_ = 0.8;
        max_linear_speed_ = 0.4;
        max_angular_speed_ = 1.5;

        has_odom_ = false;
        has_path_ = false;

        ROS_INFO("Simple Pure Pursuit node started. You can set goal via Rviz 2D Nav Goal.");
    }

    void odomCallback(const nav_msgs::Odometry::ConstPtr& msg)
    {
        robot_pose_.x = msg->pose.pose.position.x;
        robot_pose_.y = msg->pose.pose.position.y;
        robot_pose_.theta = tf::getYaw(msg->pose.pose.orientation);
        current_speed_ = msg->twist.twist.linear.x;
        has_odom_ = true;
    }

    void pathCallback(const nav_msgs::Path::ConstPtr& msg)
    {
        path_ = *msg;
        has_path_ = true;
        ROS_INFO("Received external path with %lu waypoints", path_.poses.size());
    }

    // ========= 新增：处理 2D Nav Goal =========
    void goalCallback(const geometry_msgs::PoseStamped::ConstPtr& goal_msg)
    {
        if (!has_odom_) {
            ROS_WARN("No odometry yet, cannot generate path to goal.");
            return;
        }

        double goal_x = goal_msg->pose.position.x;
        double goal_y = goal_msg->pose.position.y;

        // 生成从当前位置到目标点的直线路径（用 50 个点插值）
        nav_msgs::Path new_path;
        new_path.header.stamp = ros::Time::now();
        new_path.header.frame_id = "odom";

        int num_points = 50;
        for (int i = 0; i <= num_points; i++)
        {
            double ratio = (double)i / num_points;
            geometry_msgs::PoseStamped p;
            p.pose.position.x = robot_pose_.x + ratio * (goal_x - robot_pose_.x);
            p.pose.position.y = robot_pose_.y + ratio * (goal_y - robot_pose_.y);
            p.pose.position.z = 0.0;
            p.pose.orientation.w = 1.0;
            new_path.poses.push_back(p);
        }

        path_ = new_path;
        has_path_ = true;
        ROS_INFO("Generated straight path to goal (%.2f, %.2f)", goal_x, goal_y);
    }

    void run()
    {
        if (!has_odom_)
        {
            ROS_WARN_THROTTLE(2, "Waiting for /odom message...");
            return;
        }

        // 如果没有路径，自动生成默认直线（方便测试）
        if (!has_path_)
        {
            generateDummyPath();
        }

        geometry_msgs::Pose2D target = findLookaheadPoint();

        double local_x, local_y;
        transformToRobotFrame(target, local_x, local_y);

        double curvature = 0.0;
        double dist_sq = local_x * local_x + local_y * local_y;
        if (dist_sq > 0.001)
        {
            curvature = (2.0 * local_y) / dist_sq;
        }

        double angular = max_linear_speed_ * curvature;
        if (angular > max_angular_speed_) angular = max_angular_speed_;
        if (angular < -max_angular_speed_) angular = -max_angular_speed_;

        double linear = max_linear_speed_;
        double abs_curvature = std::abs(curvature);
        if (abs_curvature > 0.5)
        {
            linear = max_linear_speed_ * (1.0 / (1.0 + abs_curvature));
        }

        geometry_msgs::Pose2D goal_pose;
        goal_pose.x = path_.poses.back().pose.position.x;
        goal_pose.y = path_.poses.back().pose.position.y;
        goal_pose.theta = 0;
        double dist_to_goal = distance(robot_pose_, goal_pose);
        if (dist_to_goal < lookahead_distance_)
        {
            linear = linear * (dist_to_goal / lookahead_distance_);
        }

        if (linear < 0.01) linear = 0.0;

        geometry_msgs::Twist cmd;
        cmd.linear.x = linear;
        cmd.angular.z = angular;
        cmd_pub_.publish(cmd);

        ROS_DEBUG("Lookahead (global): [%.2f, %.2f], local: [%.2f, %.2f], curvature: %.2f, cmd: [%.2f, %.2f]",
                  target.x, target.y, local_x, local_y, curvature, linear, angular);
    }

private:
    void generateDummyPath()
    {
        nav_msgs::Path dummy;
        dummy.header.stamp = ros::Time::now();
        dummy.header.frame_id = "odom";

        for (int i = 0; i <= 50; i++)
        {
            geometry_msgs::PoseStamped p;
            p.pose.position.x = i * 0.1;
            p.pose.position.y = 0.0;
            p.pose.position.z = 0.0;
            p.pose.orientation.w = 1.0;
            dummy.poses.push_back(p);
        }
        path_ = dummy;
        has_path_ = true;
        ROS_INFO("No path received, using default X-axis line (0~5m).");
    }

    double distance(const geometry_msgs::Pose2D& p1, const geometry_msgs::Pose2D& p2)
    {
        return std::sqrt(std::pow(p1.x - p2.x, 2) + std::pow(p1.y - p2.y, 2));
    }
    double distance(const geometry_msgs::Pose2D& p1, const geometry_msgs::Point& p2)
    {
        return std::sqrt(std::pow(p1.x - p2.x, 2) + std::pow(p1.y - p2.y, 2));
    }

    geometry_msgs::Pose2D findLookaheadPoint()
    {
        if (path_.poses.size() < 2)
        {
            geometry_msgs::Pose2D last;
            last.x = path_.poses.back().pose.position.x;
            last.y = path_.poses.back().pose.position.y;
            last.theta = 0;
            return last;
        }

        for (size_t i = 0; i < path_.poses.size() - 1; i++)
        {
            const auto& p1 = path_.poses[i].pose.position;
            const auto& p2 = path_.poses[i+1].pose.position;

            geometry_msgs::Pose2D p1_2d;
            p1_2d.x = p1.x; p1_2d.y = p1.y; p1_2d.theta = 0;
            geometry_msgs::Pose2D p2_2d;
            p2_2d.x = p2.x; p2_2d.y = p2.y; p2_2d.theta = 0;

            double d1 = distance(robot_pose_, p1_2d);
            double d2 = distance(robot_pose_, p2_2d);

            if (d1 <= lookahead_distance_ && d2 >= lookahead_distance_)
            {
                double ratio = (lookahead_distance_ - d1) / (d2 - d1 + 0.0001);
                geometry_msgs::Pose2D target;
                target.x = p1.x + ratio * (p2.x - p1.x);
                target.y = p1.y + ratio * (p2.y - p1.y);
                target.theta = 0;
                return target;
            }
        }

        const auto& last = path_.poses.back().pose.position;
        geometry_msgs::Pose2D last_pose;
        last_pose.x = last.x;
        last_pose.y = last.y;
        last_pose.theta = 0;
        return last_pose;
    }

    void transformToRobotFrame(const geometry_msgs::Pose2D& global_point,
                               double& local_x, double& local_y)
    {
        double dx = global_point.x - robot_pose_.x;
        double dy = global_point.y - robot_pose_.y;
        double cos_theta = std::cos(robot_pose_.theta);
        double sin_theta = std::sin(robot_pose_.theta);

        local_x = dx * cos_theta + dy * sin_theta;
        local_y = -dx * sin_theta + dy * cos_theta;
    }

    ros::NodeHandle nh_;
    ros::Publisher cmd_pub_;
    ros::Subscriber odom_sub_;
    ros::Subscriber path_sub_;
    ros::Subscriber goal_sub_;   // 新增

    nav_msgs::Path path_;
    geometry_msgs::Pose2D robot_pose_;
    double current_speed_ = 0.0;

    bool has_odom_;
    bool has_path_;

    double lookahead_distance_;
    double max_linear_speed_;
    double max_angular_speed_;
};

int main(int argc, char** argv)
{
    ros::init(argc, argv, "simple_pure_pursuit");
    SimplePurePursuit controller;

    ros::Rate rate(20);
    while (ros::ok())
    {
        ros::spinOnce();
        controller.run();
        rate.sleep();
    }
    return 0;
}