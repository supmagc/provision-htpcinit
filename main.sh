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
request_variable "BOOT_TIMEOUT" "boot timeout"

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
  pulseaudio pavucontrol \
  kodi \
  samba \
  steam retroarch

# Remove no longer needed packages
apt-get autoremove -y

# Create and configure ssl
mkdir -p /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME /home/$USERNAME/.ssh
chmod -R u=rwX,go=rX /home/$USERNAME/.ssh

# Force locale and keymap settings
locale-gen "$LOCALE_LANG"
localectl set-x11-keymap "$LOCALE_KEYMAP"
localectl set-keymap "$LOCALE_KEYMAP"
cp templates/htpcinit-display-setup /usr/local/bin/htpcinit-display-setup
chmod 0755 /usr/local/bin/htpcinit-display-setup
echo "[Seat:*]" > /etc/lightdm/lightdm.conf.d/75-htpcinit-display-setup.conf
echo "display-setup-script=htpcinit-display-setup" >> /etc/lightdm/lightdm.conf.d/75-htpcinit-display-setup.conf
chmod 0644 /etc/lightdm/lightdm.conf.d/75-htpcinit-display-setup.conf

# Disable unneeded xsessions and add htpc xsession
mkdir -p /usr/share/xsessions/hidden
for f in $(ls /usr/share/xsessions | grep -e ".*\.desktop$"); do
  if [ ! $f == htpc.desktop ] && [ ! $f == kodi.desktop ] && [ ! $f == Lubuntu.desktop ] && [ ! $f == xubuntu.desktop ]; then
	sudo dpkg-divert --rename \
	  --divert /usr/share/xsessions/hidden/$f \
	  --add /usr/share/xsessions/$f
  fi
done
cp templates/htpc.desktop /usr/share/xsessions/htpc.desktop
chmod u=rwX,go=rX /usr/share/xsessions/*

# Add xsession entrypoint
cp templates/htpcinit /usr/local/bin/htpcinit
chmod 0755 /usr/local/bin/htpcinit

# Enable autologon
echo "[Seat:*]" > /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "autologin-user=$USERNAME" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "autologin-user-timeout=0" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
echo "user-session=htpc" >> /etc/lightdm/lightdm.conf.d/75-htpcinit.conf
chmod 0644 /etc/lightdm/lightdm.conf.d/75-htpcinit.conf

# Install lirc from source

# Install lirc config

# Configure nvidia
if [ "$(lspci -v | grep nvidia)" ]; then
  apt-get install -y nvidia-364 vdpauinfo
  nvidia-xconfig --no-use-edid-dpi
  sed -i "/DPI/d" /etc/X11/xorg.conf
  sed -i "/UseEdidDpi/i\
\    Option         \"DPI\" \"$SCREEN_DPI x $SCREEN_DPI\"" /etc/X11/xorg.conf
fi

# Download and install chrome
if [ -z $(which google-chrome) ]; then
  wget -O /var/tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install /var/tmp/chrome.deb
fi

# Change GRUB config
sed -i "s/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=$BOOT_TIMEOUT/" /etc/default/grub
update-grub2

# Basic configuration for kodi
mkdir -p /home/$USERNAME/.kodi/userdata
cp templates/advancedsettings.xml  /home/$USERNAME/.kodi/userdata/advancedsettings.xml
chown -R $USERNAME:$USERNAME /home/$USERNAME/.kodi
chmod -R a=,u=rwX,go=rX /home/$USERNAME/.kodi

# Install plymouth theme

# Install samba config
sed -e "s/{HOSTNAME}/$HOSTNAME/" -e "s/{WORKGROUO}/$WORKGROUP/" templates/smb.conf > /etc/samba/smb.conf
systemctl restart smbd.service
systemctl restart nmbd.service

# Configure network
hostname "$HOSTNAME"
sed -i "/127.0.0.1/d" /etc/hosts
sed -i "1 i 127.0.0.1\t$HOSTNAME" /etc/hosts
resolvconf -u
nmcli connection modify "$NET_CONN" ipv4.method "manual" ipv4.dns "$NET_DNS" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GATE"
systemctl restart network-manager.service
