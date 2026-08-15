#include<ros/ros.h>
#include "servicelea/person.h"
bool personCallback(servicelea::person::Request &req,
servicelea::person::Response &res){
    ROS_INFO("person :name:%s age :%d sex:%d",req.name.c_str(),req.age,req.sex);

    res.result="OK";
    return true;
}
int main(int argc,char**argv){
    ros::init(argc,argv,"person_server");
    ros::NodeHandle n;
    ros::ServiceServer person_service=n.advertiseService("/show_person",personCallback);

    ROS_INFO("ready to show person informtion");
    ros::spin();
    return 0;
}