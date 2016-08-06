#!/bin/bash

if [ $(id -u) -ne 0 ]; then
  echo "HtpcInit main.sh must be run as root"
  exit
fi

if [ $(echo $DESKTOP_SESSION) -ne "Lubuntu" ]; then
  echo "HtpcInit is only compatible with x64 Lubuntu"
  exit
fi

if [ $(uname -m) -ne "x86_64" ]; then
  echo "HtpcInit is only compatible with x64 Lubuntu"
  exit
fi

if [ ! $DISPLAY ]; then
  export DISPLAY=:0
fi

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

function copy_and_parse_file {
  local FILE_SOURCE_PATH="$1"
  local FILE_TARGET_PATH="$2"
  if [ -z "$FILE_TARGET_PATH" ]; then
    FILE_TARGET_PATH="$FILE_SOURCE_PATH"
  else
    cp -v "$FILE_SOURCE_PATH" "$FILE_TARGET_PATH"
  fi
  for i in ${!DEFAULT_*}; do
    local VAR_NAME=${i:8}
	local VAR_VALUE="${!VAR_NAME}"
	local VAR_VALUE="${VAR_VALUE//\//\\\/}"
    sed -i "s/{$VAR_NAME}/$VAR_VALUE/" "$FILE_TARGET_PATH"
  done
  chmod 0644 "$FILE_TARGET_PATH"
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
request_variable "INSTALLATION" "install location"
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
  wmctrl xdotool \
  kodi \
  samba \
  steam \
  retroarch

# Remove no longer needed packages
apt-get autoremove -y

# Copy scripts etc
mkdir -vp "$INSTALLATION"
cp -vr data/* "$INSTALLATION"
chmod -R a+rX "$INSTALLATION"
chmod -R a+x "$INSTALLATION/scripts/*"

# Create and configure ssl
mkdir -vp /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
chown -vR $USERNAME /home/$USERNAME/.ssh
chmod -vR u=rwX,go=rX /home/$USERNAME/.ssh

# Force locale and keymap settings
locale-gen "$LOCALE_LANG"
localectl set-x11-keymap "$LOCALE_KEYMAP"
localectl set-keymap "$LOCALE_KEYMAP"
copy_and_parse_file "templates/75-htpcinit-display-setup.conf" "/etc/lightdm/lightdm.conf.d/75-htpcinit-display-setup.conf"

# Disable unneeded xsessions and add htpc xsession
mkdir -p /usr/share/xsessions/hidden
for f in $(ls /usr/share/xsessions | grep -e ".*\.desktop$"); do
  if [ ! $f == htpc.desktop ] && [ ! $f == kodi.desktop ] && [ ! $f == Lubuntu.desktop ]; then
	sudo dpkg-divert --rename \
	  --divert /usr/share/xsessions/hidden/$f \
	  --add /usr/share/xsessions/$f
  fi
done
copy_and_parse_file "templates/htpc.desktop" "/usr/share/xsessions/htpc.desktop"

# Enable autologon
copy_and_parse_file "templates/75-htpcinit.conf" "/etc/lightdm/lightdm.conf.d/75-htpcinit.conf"

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
  apt-get install -y /var/tmp/chrome.deb
fi

# Change GRUB config
sed -i "s/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=$BOOT_TIMEOUT/" /etc/default/grub
update-grub2

# Basic configuration for kodi
mkdir -p /home/$USERNAME/.kodi/userdata
copy_and_parse_file "templates/advancedsettings.xml"  "/home/$USERNAME/.kodi/userdata/advancedsettings.xml"
chown -R $USERNAME /home/$USERNAME/.kodi
chmod -R a=,u=rwX,go=rX /home/$USERNAME/.kodi

# Install plymouth theme

# Install samba config
copy_and_parse_file "templates/smb.conf" "/etc/samba/smb.conf"
systemctl restart smbd.service
systemctl restart nmbd.service

# Configure network
hostname "$HOSTNAME"
sed -i "/127.0.0.1/d" /etc/hosts
sed -i "1 i 127.0.0.1\t$HOSTNAME" /etc/hosts
resolvconf -u
nmcli connection modify "$NET_CONN" ipv4.method "manual" ipv4.dns "$NET_DNS" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GATE"
systemctl restart network-manager.service
