#include<ros/ros.h>
#include"servicelea/person.h"
int main(int argc,char**argv){
    ros::init(argc,argv,"person_client");
    ros::NodeHandle node;
    ros::service::waitForService("/show_person");
    ros::ServiceClient person_client=node.serviceClient<servicelea::person>("/show_person");
    servicelea::person srv;
    srv.request.name="tom";
    srv.request.age=20;
    srv.request.sex=servicelea::person::Request::male;

    ROS_INFO("call service to show person [naem:%s ,age:%d,sex:%d]",srv.request.name.c_str(),srv.request.age,srv.request.sex);
    person_client.call(srv);
    ROS_INFO("show person result : %s",srv.response.result.c_str());
    return 0;
}