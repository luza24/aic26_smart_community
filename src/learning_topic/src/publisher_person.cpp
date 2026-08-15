#include<ros/ros.h>
#include"learning_topic/person.h"
int main(int argc,char **argv){
    ros::init(argc,argv,"publisher_person");
    ros::NodeHandle n;
    ros::Publisher person_info_pub=n.advertise<learning_topic::person>("/person_info",10);
    ros::Rate loop_rate(1);

    int cont=0;
    while(ros::ok()){
        learning_topic::person person_msg;
        person_msg.name="tom";
        person_msg.age=18;
        person_msg.sex =learning_topic::person::male;
        person_info_pub.publish(person_msg);
        ROS_INFO("Publish Person Info:name:%s age:%d sex",person_msg.name.c_str(),person_msg.age,person_msg.sex);
        loop_rate.sleep();

    }
    return 0;
}