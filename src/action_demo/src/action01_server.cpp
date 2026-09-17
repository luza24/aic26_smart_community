#include "ros/ros.h"
#include "actionlib/server/simple_action_server.h"
#include "action_demo/AddintsAction.h"

typedef  actionlib::SimpleActionServer<action_demo::AddintsAction> Server;
void cb(const action_demo::AddintsGoalConstPtr &goal,Server* server){
    int num=goal->num;
    ROS_INFO("目标值：%d",num);
    int result =0 ;
    action_demo::AddintsFeedback feedback;
    ros::Rate rate(10);
    for(int i=1;i<=num;i++){
        result +=i;
        feedback.progress_bar=i/(double)num;
        server->publishFeedback(feedback);
        rate.sleep();
    }
    action_demo::AddintsResult r;
    r.result=result;
    server->setSucceeded(r);
    ROS_INFO("最终结果：%d",r.result);
}
int main(int argc, char  *argv[])
{
    setlocale(LC_ALL,"");
    ROS_INFO("action服务端实现");
    ros::init(argc,argv,"addints_server");
    ros::NodeHandle nh;
    
    //actionlib::SimpleActionServer<action_demo::AddintsAction>;
    Server server(nh,"addInts",boost::bind(&cb,_1,&server),false);
    server.start();
    ros::spin();
    return 0;
}
