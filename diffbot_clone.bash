#!/usr/bin/env bash
set -e

# Install git and pip if needed
for pkg in git python3-pip; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        echo "${pkg} uninstalled, install now..."
        sudo apt-get update
        sudo apt-get install -y "$pkg"
    fi
done

# rosdepc is not in apt. Install it with pip if missing.
if ! command -v rosdepc >/dev/null 2>&1; then
    echo "rosdepc not found, installing with pip3..."
    sudo pip3 install rosdepc
    sudo rosdepc init || true
    rosdepc update || true
fi

WORKSPACE="$HOME/catkin_ws"
SRC="$WORKSPACE/src"

mkdir -p "$SRC"
cd "$SRC"

for url in \
    https://github.com/ros-mobile-robots/diffbot \
    https://github.com/ros-mobile-robots/rplidar_ros \
    https://github.com/UbiquityRobotics/raspicam_node \
    https://github.com/PickNikRobotics/rosparam_shortcuts
do
    repo=$(basename "$url")
    if [ ! -d "$repo" ]; then
        git clone "https://gh-proxy.org/${url}.git" -b noetic-devel
    else
        echo "$repo already exists, skipping"
    fi
done

cd "$WORKSPACE"

# Make sure ROS Noetic is sourced
source /opt/ros/noetic/setup.bash

rosdepc init
rosdepc install --from-paths src --ignore-src -r -y
catkin_make

source devel/setup.bash
roslaunch diffbot_control diffbot.launch