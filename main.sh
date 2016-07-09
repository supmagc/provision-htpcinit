#!/bin/bash

source templates/default.conf
if [ -f config.conf ]; then
  source config.conf
fi

# Add ppa's
sudo add-apt-repository ppa:team-xbmc/ppa
sudo add-apt-repository ppa:graphics-drivers/ppa

# Update apt
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y

# Install additional software
sudo apt-get install -y openssl
sudo apt-get install -y lxkeymap
sudo apt-get install -y pulseaudio pavucontrol
sudo apt-get install -y nvidia-364 vdpauinfo
sudo apt-get install -y kodi
sudo apt-get install -y samba

#create and configure ssl

#configure network

#force locale and keymap settings

#disable unneeded xsessions

#create custom xsession to always enable openbox

#install steam

#install lirc from source

#install lirc config

#install samba config
sudo sed 's/{HOSTNAME}/$HOSTNAME/^; s/{WORKGROUO}/$WORKGROUP/' templates/smb.conf > /etc/samba/smb.conf
sudo service samba restart
