#include "ros/ros.h"
#include "actionlib/client/simple_action_client.h"
#include "action_demo/AddintsAction.h"

void done_cb(const actionlib::SimpleClientGoalState &state, const action_demo::AddintsResultConstPtr &result){
     if (state.state_ == state.SUCCEEDED)
    {
        ROS_INFO("最终结果:%d",result->result);
    } else {
        ROS_INFO("任务失败！");
    }

}
void active_cb(){
    ROS_INFO("服务已经被激活....");

}
void feedback_cb(const action_demo::AddintsFeedbackConstPtr &feedback){
     ROS_INFO("当前进度:%.2f",feedback->progress_bar);
}

int main(int argc, char *argv[])
{
    /* code */
    setlocale(LC_ALL,"");
    ros::init( argc,argv,"addInts_client");
    ros::NodeHandle nh;
    actionlib::SimpleActionClient<action_demo::AddintsAction> client(nh,"addInts");
    client.waitForServer();
    action_demo::AddintsGoal goal;
    goal.num=10;
    
    client.sendGoal(goal,&done_cb,&active_cb,&feedback_cb);
    ros::spin();
    return 0;
}
