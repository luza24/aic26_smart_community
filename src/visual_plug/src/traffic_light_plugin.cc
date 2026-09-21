// TrafficLightControllerPlugin (WorldPlugin)
// 通过 transport ~/visual 消息控制门架红绿灯的发光透镜, 实现 红(10s)->绿(15s)->黄(5s) 循环。
//
// 关键 (从 gzserver 报错确认):
//   msgs::Visual 的 parent_name 是【必填字段】。消息必须:
//     name         = visual 短名 (如 "red_visual")
//     parent_name  = 所属 model 名 (如 "traffic_light_top_red_lens")
//   缺 parent_name 时 publish 直接报错丢弃, 灯不会变。
//
// 用法: 在 <world> 下挂载:
//   <plugin name="traffic_light_controller" filename="libtraffic_light_plugin.so">
//     <red>10</red> <green>15</green> <yellow>5</yellow>
//     <group>traffic_light_top</group>
//     <group>traffic_light_bottom</group>
//   </plugin>
//
// 约定: 每组红绿灯 = 1 主体 + 3 发光透镜独立 model:
//   <prefix>             -> 主体
//   <prefix>_red_lens    -> link 'lens', visual 'red_visual'
//   <prefix>_yellow_lens -> link 'lens', visual 'yellow_visual'
//   <prefix>_green_lens  -> link 'lens', visual 'green_visual'
#include <gazebo/gazebo.hh>
#include <gazebo/common/common.hh>
#include <gazebo/physics/physics.hh>
#include <gazebo/transport/transport.hh>
#include <gazebo/msgs/msgs.hh>
#include <ignition/math/Color.hh>
#include <string>
#include <vector>
#include <functional>

namespace gazebo
{
  class TrafficLightControllerPlugin : public WorldPlugin
  {
    private: enum LightState { RED, GREEN, YELLOW };

    private: physics::WorldPtr world;
    private: event::ConnectionPtr updateConnection;
    private: transport::NodePtr node;
    private: transport::PublisherPtr visPub;

    private: LightState state;
    private: common::Time stateStartTime;

    private: double redDur, greenDur, yellowDur;
    private: std::vector<std::string> groups;

    public: void Load(physics::WorldPtr _world, sdf::ElementPtr _sdf)
    {
      this->world = _world;

      this->redDur    = _sdf->HasElement("red")    ? _sdf->Get<double>("red")    : 10.0;
      this->greenDur  = _sdf->HasElement("green")  ? _sdf->Get<double>("green")  : 15.0;
      this->yellowDur = _sdf->HasElement("yellow") ? _sdf->Get<double>("yellow") : 5.0;

      if (_sdf->HasElement("group"))
      {
        sdf::ElementPtr g = _sdf->GetElement("group");
        while (g)
        {
          this->groups.push_back(g->Get<std::string>());
          g = g->GetNextElement("group");
        }
      }

      // transport 消息 (server -> client), 挂在 world 作用域
      this->node = transport::NodePtr(new transport::Node());
      this->node->Init(this->world->Name());
      this->visPub = this->node->Advertise<msgs::Visual>("~/visual");

      this->state = RED;
      std::string init = _sdf->HasElement("initial") ? _sdf->Get<std::string>("initial") : "red";
      if (init == "green")  this->state = GREEN;
      if (init == "yellow") this->state = YELLOW;

      this->stateStartTime = this->world->SimTime();

      this->updateConnection = event::Events::ConnectWorldUpdateBegin(
          std::bind(&TrafficLightControllerPlugin::OnUpdate, this));

      // 首次立即应用 (红灯亮)
      this->ApplyState();

      gzmsg << "[TrafficLight] LOADED world='" << this->world->Name()
            << "' groups=" << this->groups.size()
            << " red=" << this->redDur << "s green=" << this->greenDur
            << "s yellow=" << this->yellowDur << "s" << std::endl;
    }

    private: void OnUpdate()
    {
      double limit;
      switch (this->state)
      {
        case RED:    limit = this->redDur;    break;
        case GREEN:  limit = this->greenDur;  break;
        default:     limit = this->yellowDur; break;
      }

      common::Time now = this->world->SimTime();
      if ((now - this->stateStartTime).Double() >= limit)
      {
        this->stateStartTime = now;
        switch (this->state)
        {
          case RED:    this->state = GREEN;  break;
          case GREEN:  this->state = YELLOW; break;
          case YELLOW: this->state = RED;    break;
        }
        gzmsg << "[TrafficLight] -> "
              << (this->state == RED ? "RED" :
                 (this->state == GREEN ? "GREEN" : "YELLOW")) << std::endl;
        this->ApplyState();
      }
    }

    private: void ApplyState()
    {
      for (const auto &prefix : this->groups)
      {
        SetLens(prefix + "_red_lens",    "red_visual",    this->state == RED);
        SetLens(prefix + "_yellow_lens", "yellow_visual", this->state == YELLOW);
        SetLens(prefix + "_green_lens",  "green_visual",  this->state == GREEN);
      }
    }

    private: void SetLens(const std::string &_lensModel, const std::string &_visualName, bool _on)
    {
      ignition::math::Color off(0.04, 0.04, 0.04, 1.0);
      ignition::math::Color black(0.0, 0.0, 0.0, 1.0);
      ignition::math::Color red(1.0, 0.005, 0.005, 1.0);
      ignition::math::Color green(0.005, 1.0, 0.02, 1.0);
      ignition::math::Color yellow(1.0, 0.72, 0.005, 1.0);

      ignition::math::Color diffuse, emissive;
      if (!_on)
      {
        diffuse  = off;
        emissive = black;
      }
      else if (_visualName == "red_visual")    { diffuse = red;    emissive = ignition::math::Color(0.58, 0.003, 0.003, 1.0);   }
      else if (_visualName == "yellow_visual") { diffuse = yellow; emissive = ignition::math::Color(0.58, 0.40,  0.003, 1.0); }
      else                                     { diffuse = green;  emissive = ignition::math::Color(0.003, 0.58, 0.012, 1.0);  }

      msgs::Visual msg;
      // 渲染端按 parent_name + "::" + name 拼接查找,
      // 所以 name = link::visual 两段, 拼成 model::link::visual 三段才正确。
      msg.set_name("lens::" + _visualName);
      msg.set_parent_name(_lensModel);
      msgs::Set(msg.mutable_material()->mutable_ambient(), diffuse * 0.8);
      msgs::Set(msg.mutable_material()->mutable_diffuse(),  diffuse);
      msgs::Set(msg.mutable_material()->mutable_emissive(), emissive);
      this->visPub->Publish(msg);
    }
  };

  GZ_REGISTER_WORLD_PLUGIN(TrafficLightControllerPlugin)
}
