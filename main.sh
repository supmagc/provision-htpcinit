#!/bin/bash

echo "Loading default config:"
cat ./templates/default.conf
source ./templates/default.conf

if [ -f ~/.config/htpcinit.user.conf ]; then
  echo "Loading overriding user config:"
  cat ~/.config/htpcinit.user.conf
  source ~/.config/htpcinit.user.conf
fi

function request_variable {
  local VAR_NAME="$1"
  local VAR_DEFAULT_NAME="DEFAULT_$VAR_NAME"
  local VAR_DESCRIPTION="$2"
  read -p "What is your $VAR_DESCRIPTION [default: ${!VAR_DEFAULT_NAME}]? " VAR
  if [ -z "$VAR" ]; then VAR="${!VAR_DEFAULT_NAME}"; fi
  eval "$VAR_DEFAULT_NAME=\"$VAR\""
  eval "$VAR_NAME=\"$VAR\""
}

# Request userdata updates
echo "Current IP:"
ip addr
request_variable "NET_IP" "network ip"
request_variable "NET_DNS" "dns servers"
request_variable "NET_GATE" "network gateway"
echo "Available network connections:"
nmcli connection
request_variable "NET_CONN" "network connection"
request_variable "USERNAME" "username"
request_variable "HOSTNAME" "hostname"
request_variable "WORKGROUP" "workgroup"
request_variable "SSH_KEY" "ssh key"
request_variable "LOCALE_LANG" "system language"
request_variable "LOCALE_KEYMAP" "default keymap"
request_variable "SCREEN_DPI" "screen dpi"

echo "#User specified overrides for HtpcInit configuration" > ~/.config/htpcinit.user.conf
for i in ${!DEFAULT_*}; do
  echo "$i=\"${!i}\"" >> ~/.config/htpcinit.user.conf
done

# Add ppa's
add-apt-repository main -y
add-apt-repository universe -y
add-apt-repository restricted -y
add-apt-repository multiverse -y
add-apt-repository ppa:team-xbmc/ppa -y
add-apt-repository ppa:graphics-drivers/ppa -y
add-apt-repository ppa:libretro/testing -y

# Update apt
apt-get update -y
apt-get upgrade -y
apt-get dist-upgrade -y

# Install additional software
apt-get install -y openssl \
  lxkeymap \
  pulseaudio pavucontrol \
  nvidia-364 vdpauinfo \
  kodi \
  samba \
  steam retroarch

# Remove no longer needed packages
apt-get autoremove -y

# Create and configure ssl
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chown $USERNAME /home/$USERNAME/.ssh/authorized_keys
chmod 0744 /home/$USERNAME/.ssh/authorized_keys

# Configure network
hostname "$HOSTNAME"
sed -i "/127.0.0.1/d" /etc/hosts
sed -i "1 i 127.0.0.1\t$HOSTNAME" /etc/hosts
resolvconf -u
nmcli connection modify "$NET_CONN" ipv4.method "manual" ipv4.dns "$NET_DNS" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GATE"
systemctl restart network-manager.service

# Force locale and keymap settings
locale-gen "$LOCALE_LANG"
localectl set-x11-keymap "$LOCALE_KEYMAP"
localectl set-keymap "$LOCALE_KEYMAP"

# Disable unneeded xsessions and add htpc xsession
mkdir /usr/share/xsessions/hidden
for f in $(ls /usr/share/xsessions | grep -e ".*\.desktop$"); do
  if [ ! $f == htpc.desktop ] && [ ! $f == kodi.desktop ] && [ ! $f == Lubuntu.desktop ]; then
	sudo dpkg-divert --rename \
	  --divert /usr/share/xsessions/hidden/$f \
	  --add /usr/share/xsessions/$f
  fi
done
cp templates/htpc.desktop /usr/share/xsessions/htpc.desktop
chown -R root:root /usr/share/xsessions/*
chmod u=rwX,go=rX /usr/share/xsessions/*

# Add xsession entrypoint
cp templates/htpcinit /usr/local/bin/htpcinit
chown root:root /usr/local/bin/htpcinit
chmod 0755 /usr/local/bin/htpcinit

# Enable autologon
echo "[Seat:*]" > /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "autologin-user=$USERNAME" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "autologin-user-timeout=0" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "user-session=htpc" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
chown root:root /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
chmod 0755 /etc/lightdm/lightdm.conf.d/75-htpcinit.conf

# Install lirc from source

# Install lirc config

# Configure nvidia
nvidia-xconfig --no-use-edid-dpi
sed -i "/UseEdidDpi/i\
\    Option         \"DPI\" \"$SCREEN_DPI x $SCREEN_DPI\"" /etc/X11/xorg.conf

# Download and install chrome
if [ -z $(which google-chrome) ]; then
  wget -O /var/tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  dpkg -i /var/tmp/chrome.deb
fi


# Basic configuration for kodi

#install samba config
sed -e "s/{HOSTNAME}/$HOSTNAME/" -e "s/{WORKGROUO}/$WORKGROUP/" templates/smb.conf > /etc/samba/smb.conf
systemctl restart smbd.service
systemctl restart nmbd.service
