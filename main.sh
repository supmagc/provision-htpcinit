#!/bin/bash

# Add ppa's
sudo add-apt-repository ppa:team-xbmc/ppa
sudo add-apt-repository ppa:graphics-drivers/ppa

# Update apt
sudo apt-get update
sudo apt-get upgrade

# Install additional software
sudo apt-get install lxkeymap
sudo apt-get install pulseaudio pavucontrol
sudo apt-get install nvidia-graphics-driver-364 vdpauinfo
sudo apt-get install kodi
sudo apt-get install samba

#force locale and keymap settings

#install graphics-drivers ppa

#install nvidia graphics drivers

#disable unneeded xsessions

#create custom xsession to always enable openbox

#install steam

#install lirc from source

#install lirc config

#install samba config