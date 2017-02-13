#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
  echo "HtpcInit main.sh must be run as root"
  exit
fi

if [[ $(echo $DESKTOP_SESSION) -ne "Lubuntu" ]]; then
  echo "HtpcInit is only compatible with x64 Lubuntu"
  exit
fi

if [[ $(uname -m) -ne "x86_64" ]]; then
  echo "HtpcInit is only compatible with x64 Lubuntu"
  exit
fi

if [[ ! $DISPLAY ]]; then
  export DISPLAY=:0
fi

echo "Loading default config:"
cat ./templates/default.conf
source ./templates/default.conf

if [[ -f ~/.config/htpcinit.user.conf ]]; then
  echo "Loading overriding user config:"
  cat ~/.config/htpcinit.user.conf
  source ~/.config/htpcinit.user.conf
fi

function request_variable {
  local VAR_NAME="$1"
  local VAR_DEFAULT_NAME="DEFAULT_$VAR_NAME"
  local VAR_DESCRIPTION="$2"
  read -p "What is your $VAR_DESCRIPTION [default: ${!VAR_DEFAULT_NAME}]? " VAR
  if [[ -z "$VAR" ]]; then VAR="${!VAR_DEFAULT_NAME}"; fi
  eval "$VAR_DEFAULT_NAME=\"$VAR\""
  eval "$VAR_NAME=\"$VAR\""
}

function copy_and_parse_file {
  local FILE_SOURCE_PATH="$1"
  local FILE_TARGET_PATH="$2"
  if [[ -z "$FILE_TARGET_PATH" ]]; then
    FILE_TARGET_PATH="$FILE_SOURCE_PATH"
  else
    cp -v "$FILE_SOURCE_PATH" "$FILE_TARGET_PATH"
  fi
  mkdir -p $(dirname "$FILE_TARGET_PATH")
  for i in ${!DEFAULT_*}; do
    local VAR_NAME=${i:8}
	local VAR_VALUE="${!VAR_NAME}"
	local VAR_VALUE="${VAR_VALUE//\//\\\/}"
    sed -i "s/{$VAR_NAME}/$VAR_VALUE/" "$FILE_TARGET_PATH"
  done
  chmod 0644 "$FILE_TARGET_PATH"
}

function add_files_to_kodi_sources {
  local KS_FILE="$1"
  local KS_NAME="$2"
  local KS_PATH="$3"
  if [[ -z "$(xmlstarlet sel -t -v "/sources/files/source[name='$KS_NAME']" "$KS_FILE")" ]]; then
    if [[ -z "$(xmlstarlet sel -t -v "/sources/files/source" "$KS_FILE")" ]]; then
      xmlstarlet ed -P -L \
        -s "/sources/files" -t elem -n source -v "" \
        "$KS_FILE"
    else
      xmlstarlet ed -P -L \
        -i "/sources/files/source[1]" -t elem -n source -v "" \
        "$KS_FILE"
    fi
	xmlstarlet ed -P -L \
      -s "/sources/files/source[1]" -t elem -n name -v "$KS_NAME" \
      -s "/sources/files/source[1]" -t elem -n path -v "$KS_PATH" \
      -s "/sources/files/source[1]/path" -t attr -n pathversion -v "1" \
      -s "/sources/files/source[1]" -t elem -n allowsharing -v "true" \
      "$KS_FILE"
  fi
}

function add_samba_credential_to_kodi_passwords {
  local KP_FILE="$1"
  local KP_ADDRESS="$2"
  local KP_USERNAME="$3"
  local KP_PASSWORD="$4"
  local KP_FROM="smb://$KP_ADDRESS/"
  local KP_TO="smb://$KP_USERNAME:$KP_PASSWORD@$KP_ADDRESS/"
  if [[ -z "$(xmlstarlet sel -t -v "/passwords/path[from=\"$KP_FROM\"]" "$KP_FILE")" ]]; then
    if [[ -z "$(xmlstarlet sel -t -v "/passwords/path" "$KP_FILE")" ]]; then
      xmlstarlet ed -P -L \
  	  -s "/passwords" -t elem -n path -v "" \
  	  "$KP_FILE"
    else
      xmlstarlet ed -P -L \
  	  -i "/passwords/path[1]" -t elem -n path -v "" \
  	  "$KP_FILE"
    fi
    xmlstarlet ed -P -L \
      -s "/passwords/path[1]" -t elem -n from -v "$KP_FROM" \
      -s "/passwords/path[1]" -t elem -n to -v "$KP_TO" \
      -s "/passwords/path[1]/from" -t attr -n pathversion -v "1" \
      -s "/passwords/path[1]/to" -t attr -n pathversion -v "1" \
      "$KP_FILE"	
  else
    xmlstarlet ed -P -L \
      -u "/passwords/path[from=\"$KP_FROM\"]/from" -v "$KP_FROM" \
  	  -u "/passwords/path[from=\"$KP_FROM\"]/to" -v "$KP_TO" \
  	  "$KP_FILE"
  fi
}

# Request userdata updates
echo "Current IP:"
ip addr
request_variable "NET_IP" "network ip"
request_variable "NET_DNS" "dns servers"
request_variable "NET_GATE" "network gateway"
request_variable "NAS_IP" "NAS ip"
request_variable "NAS_HOSTNAME" "NAS hostname"
request_variable "NAS_USERNAME" "NAS username"
request_variable "NAS_PASSWORD" "NAS password"
echo "Available network connections:"
nmcli connection
request_variable "NET_CONN" "network connection"
request_variable "USERNAME" "username"
request_variable "PASSWORD" "password"
request_variable "HOSTNAME" "hostname"
request_variable "DOMAIN" "domain"
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
apt-get install -y openssh-server samba nfs-common \
  xmlstarlet aptitude nitrogen \
  pulseaudio pavucontrol \
  wmctrl xdotool \
  kodi libdvd-pkg \
  steam \
  retroarch

# Remove no longer needed packages
apt-get autoremove -y

# Copy scripts etc
mkdir -vp "$INSTALLATION"
cp -vr data/* "$INSTALLATION"
chmod -R a+rX "$INSTALLATION"
chmod -R a+x "$INSTALLATION/scripts"

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
  if [[ ! $f == htpc.desktop && ! $f == kodi.desktop && ! $f == Lubuntu.desktop ]]; then
	sudo dpkg-divert --rename \
	  --divert /usr/share/xsessions/hidden/$f \
	  --add /usr/share/xsessions/$f
  fi
done
copy_and_parse_file "templates/htpc.desktop" "/usr/share/xsessions/htpc.desktop"

# Enable autologon
copy_and_parse_file "templates/75-htpcinit.conf" "/etc/lightdm/lightdm.conf.d/75-htpcinit.conf"

# Set default wallpaper
copy_and_parse_file "templates/40-htpcinit-greeter.conf" "/etc/lightdm/lightdm-gtk-greeter.conf.d/40-htpcinit-greeter.conf"
nitrogen --save --set-auto "$INSTALLATION/assets/wallpaper.png"

# Enable steam controller support
copy_and_parse_file "templates/99-steam-controller-perms.rules" "/lib/udev/rules.d/99-steam-controller-perms.rules"

# Install lirc from source

# Install lirc config

# Configure graphics
if [[ "$(lspci -v | grep nvidia)" ]]; then
  apt-get install -y nvidia-364 vdpauinfo
  nvidia-xconfig --no-use-edid-dpi
  sed -i "/DPI/d" /etc/X11/xorg.conf
  sed -i "/UseEdidDpi/i\
\    Option         \"DPI\" \"$SCREEN_DPI x $SCREEN_DPI\"" /etc/X11/xorg.conf
fi

# Configure Steam on virtualbox
if [[ -z "$(lspci -v | grep nvidia)" ]]; then
  STARTDIR=$(pwd)
  cd /home/$USERNAME/.steam/ubuntu12_32/steam-runtime/i386/usr/lib/i386-linux-gnu
  if [[ -f "libstdc++.so.6" ]]; then mv libstdc++.so.6 libstdc++.so.6.bak; fi
  cd /home/$USERNAME/.steam/ubuntu12_32/steam-runtime/amd64/usr/lib/x86_64-linux-gnu
  if [[ -f "libstdc++.so.6" ]]; then mv libstdc++.so.6 libstdc++.so.6.bak; fi
  cd "$STARTDIR"
fi

# Download and install chrome
if [[ -z $(which google-chrome) ]]; then
  wget -O /var/tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y /var/tmp/chrome.deb
fi

# Change GRUB config
sed -i "s/GRUB_TIMEOUT=[0-9]*/GRUB_TIMEOUT=$BOOT_TIMEOUT/" /etc/default/grub
update-grub2

# Configure dvd support
dpkg-reconfigure libdvd-pkg

# Mount NFS drives
sed -i '/mnt\/movies/d' /etc/fstab
sed -i '/mnt\/series/d' /etc/fstab
sed -i '/mnt\/music/d' /etc/fstab
sed -i '/mnt\/pictures/d' /etc/fstab
if [[ ! -d /mnt/movies ]]; then mkdir -pv /mnt/movies ; fi
if [[ ! -d /mnt/series ]]; then mkdir -pv /mnt/series ; fi
if [[ ! -d /mnt/music ]]; then mkdir -pv /mnt/music ; fi
if [[ ! -d /mnt/pictures ]]; then mkdir -pv /mnt/pictures ; fi
echo "$NAS_IP:/mnt/leftpool/multimedia/movies /mnt/movies nfs rw,hard,intr 0 0" >> /etc/fstab
echo "$NAS_IP:/mnt/leftpool/multimedia/series /mnt/series nfs rw,hard,intr 0 0" >> /etc/fstab
echo "$NAS_IP:/mnt/leftpool/multimedia/music /mnt/music nfs rw,hard,intr 0 0" >> /etc/fstab
echo "$NAS_IP:/mnt/leftpool/multimedia/pictures /mnt/pictures nfs rw,hard,intr 0 0" >> /etc/fstab
mount -a

# Basic configuration for kodi
KODI_USERDATA=/home/$USERNAME/.kodi/userdata
KODI_ADDONS=/home/$USERNAME/.kodi/addons
mkdir -p $KODI_USERDATA
copy_and_parse_file "templates/advancedsettings.xml" "$KODI_USERDATA/advancedsettings.xml"
if [[ ! -f "$KODI_USERDATA/sources.xml" ]]; then
  copy_and_parse_file "templates/sources.xml" "$KODI_USERDATA/sources.xml"
fi
if [[ ! -f "$KODI_USERDATA/passwords.xml" ]]; then
  copy_and_parse_file "templates/passwords.xml" "$KODI_USERDATA/passwords.xml"
fi
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "SuperRepo" "http://srp.nu/"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "Kodi Emby" "http://kodi.emby.media/"
add_samba_credential_to_kodi_passwords "$KODI_USERDATA/passwords.xml" "$NAS_IP" "$NAS_USERNAME" "$NAS_PASSWORD"
add_samba_credential_to_kodi_passwords "$KODI_USERDATA/passwords.xml" "$NAS_HOSTNAME" "$NAS_USERNAME" "$NAS_PASSWORD"
mkdir -p $KODI_ADDONS
if [[ ! -d $KODI_ADDONS/repository.supmagc ]]; then
  wget -O /var/tmp/repository.supmagc.zip https://github.com/supmagc/kodiaddons/raw/master/repository.supmagc/repository.supmagc-1.2.0.zip
  if [[ -d /var/tmp/repository.supmagc ]]; then
    rm -R /var/tmp/repository.supmagc
  fi
  unzip /var/tmp/repository.supmagc.zip -d /var/tmp/repository.supmagc
  mv -v /var/tmp/repository.supmagc $KODI_ADDONS
fi

chown -R $USERNAME /home/$USERNAME/.kodi
chmod -R a=,u=rwX,go=rX /home/$USERNAME/.kodi

# Install plymouth theme

# Install samba config and match password
copy_and_parse_file "templates/smb.conf" "/etc/samba/smb.conf"
echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -s -a $USERNAME
echo -e "$PASSWORD\n$PASSWORD" | passwd $USERNAME
systemctl restart nmbd.service

# Configure network
hostname "$HOSTNAME"
sed -i "/127.0.0.1/d" /etc/hosts
sed -i "1 i 127.0.0.1\t$HOSTNAME.$DOMAIN\t$HOSTNAME" /etc/hosts
resolvconf -u
nmcli connection modify "$NET_CONN" ipv4.method "manual" ipv4.dns "$NET_DNS" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GATE"
systemctl restart network-manager.service
