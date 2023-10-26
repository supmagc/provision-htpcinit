#!/bin/bash

set -e

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
cat ./install/default.conf
source ./install/default.conf

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
  mkdir -p $(dirname "$FILE_TARGET_PATH")
  if [[ -z "$FILE_TARGET_PATH" ]]; then
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

function add_files_to_kodi_sources {
  local KS_FILE="$1"
  local KS_TYPE="$2"
  local KS_NAME="$3"
  local KS_PATH="$4"
  if [[ -z "$(xmlstarlet sel -t -v "/sources/$KS_TYPE/source[name='$KS_NAME']" "$KS_FILE")" ]]; then
    if [[ -z "$(xmlstarlet sel -t -v "/sources/$KS_TYPE/source" "$KS_FILE")" ]]; then
      xmlstarlet ed -P -L \
        -s "/sources/$KS_TYPE" -t elem -n source -v "" \
        "$KS_FILE"
    else
      xmlstarlet ed -P -L \
        -i "/sources/$KS_TYPE/source[1]" -t elem -n source -v "" \
        "$KS_FILE"
    fi
	xmlstarlet ed -P -L \
      -s "/sources/$KS_TYPE/source[1]" -t elem -n name -v "$KS_NAME" \
      -s "/sources/$KS_TYPE/source[1]" -t elem -n path -v "$KS_PATH" \
      -s "/sources/$KS_TYPE/source[1]/path" -t attr -n pathversion -v "1" \
      -s "/sources/$KS_TYPE/source[1]" -t elem -n allowsharing -v "true" \
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

function add_kodi_addon {
  local KR_NAME="$1"
  local KR_URL="$2"

  if [[ "$KR_URL" =~ ^https?:.* ]]; then
    wget -O "/var/tmp/$KR_NAME.zip" "$KR_URL"
  else
    cp "$KR_URL" "/var/tmp/$KR_NAME.zip"
  fi
  if [[ -d "/var/tmp/$KR_NAME" ]]; then
    rm -R "/var/tmp/$KR_NAME"
  fi
  unzip "/var/tmp/$KR_NAME.zip" -d "/var/tmp"
  V_OLD="0.0.0"
  V_NEW=$(xmlstarlet sel -t -v "//addon/@version" -n "/var/tmp/$KR_NAME/addon.xml")

  if [[ -d "$KODI_ADDONS/$KR_NAME" ]]; then
    V_OLD=$(xmlstarlet sel -t -v "//addon/@version" -n "$KODI_ADDONS/$KR_NAME/addon.xml")
  fi

  if printf "%s\n%s\n" "$V_OLD" "$V_NEW" | sort --check=quiet -V; then
    cp -vfr "/var/tmp/$KR_NAME" $KODI_ADDONS
  fi

  rm -fv "/var/tmp/$KR_NAME.zip"
  rm -fvr "/var/tmp/$KR_NAME"
}

function add_nfs_mount {
  local KA_NAME="$1"
  sed -i "/mnt\\/$KA_NAME/d" /etc/fstab
  if [[ ! -d /mnt/$KA_NAME ]]; then mkdir -pv /mnt/$KA_NAME ; fi
  echo "$NAS_IP:/mnt/leftpool/multimedia/$KA_NAME /mnt/$KA_NAME nfs _netdev,rw,hard,intr,bg 0 0" >> /etc/fstab
}

function add_or_replace_line_in_file {
  local ARF_FILE="$1"
  local ARF_SEARCH="$2"
  local ARF_ADD="$3"
  if [[ -z $(grep "^$ARF_SEARCH" "$ARF_FILE") ]]; then
    echo "$ARF_ADD" >> "$ARF_FILE"
  else
    sed -i "s)^$ARF_SEARCH.*$)$ARF_ADD)" "$ARF_FILE"
  fi
}

function set_rights {
    local SR_PATH="$1"
    chown -vR $USERNAME:$USERNAME "$SR_PATH"
    chmod -vR a=,u=rwX,go=rX "$SR_PATH"
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
request_variable "SCREEN_RESOLUTION" "screen resolution"
ls -al data/assets/wallpaper*
request_variable "SCREEN_WALLPAPER" "screen wallpaper"
request_variable "BOOT_TIMEOUT" "boot timeout"

mkdir -p /root/.config
if [[ ! -f /root/.config/htpcinit.user.conf ]]; then touch /root/.config/htpcinit.user.conf ; fi
echo "#User specified overrides for HtpcInit configuration" > /root/.config/htpcinit.user.conf
for i in ${!DEFAULT_*}; do
  echo "$i=\"${!i}\"" >> /root/.config/htpcinit.user.conf
done

mkdir -p /home/$USERNAME/.config
if [[ ! -f /home/$USERNAME/.config/htpcinit.user.conf ]]; then touch /home/$USERNAME/.config/htpcinit.user.conf ; fi
echo "#User specified exported variables for HtpcInit configuration" > /home/$USERNAME/.config/htpcinit.user.conf
FIELDS=(NET_IP NET_DNS NET_GATE NAS_IP NAS_HOSTNAME NAS_USERNAME NAS_PASSWORD HOSTNAME DOMAIN WORKGROUP)
for i in ${FIELDS[@]}; do
  n="DEFAULT_$i"
  echo "$i=\"${!n}\"" >> /home/$USERNAME/.config/htpcinit.user.conf
done
set_rights /home/$USERNAME/.config/htpcinit.user.conf

# Add ppa's
add-apt-repository main -y
add-apt-repository universe -y
add-apt-repository restricted -y
add-apt-repository multiverse -y
add-apt-repository ppa:team-xbmc/ppa -y
add-apt-repository ppa:graphics-drivers/ppa -y
# add-apt-repository ppa:libretro/testing -y

# Add extra package repository while  waiting for WSDD to be added to Debian
curl -L https://pkg.ltec.ch/public/conf/ltec-ag.gpg.key | sudo apt-key add -
add-apt-repository "deb https://pkg.ltec.ch/public/ focal main" -y

# Update apt
apt-get update -y
apt-get upgrade -y
#apt-get dist-upgrade -y

# Install additional software
apt-get install -y openssh-server \
  nitrogen plymouth-x11 \
  samba smbclient \
  nfs-common \
  xmlstarlet aptitude \
  pulseaudio alsa-base alsa-utils pavucontrol \
  wmctrl xdotool \
  nginx resolvconf \
  bluez

# Install kodi stuff
apt-get install --install-suggests -y \
  kodi libdvd-pkg \
  kodi-eventclients-kodi-send \
  kodi-inputstream-* \
  kodi-visualization-* \
  kodi-peripheral-* \
  kodi-game-* \
  kodi-vfs-* \
  kodi-pvr-*

# Install Steam stuff
apt-get install -y \
  steam

# Remove unwanted packages
#apt-get remove -y os-prober

# Remove no longer needed packages
apt-get autoremove -y

# Copy scripts etc
mkdir -vp "$INSTALLATION"
cp -vr data/* "$INSTALLATION"
chmod -R a+rX "$INSTALLATION"
chmod -R a+x "$INSTALLATION/scripts"
add_or_replace_line_in_file "/home/$USERNAME/.profile" "PATH=\"$INSTALLATION/scripts:"'$PATH"' "PATH=\"$INSTALLATION/scripts:"'$PATH"'

# Create and configure ssl
mkdir -vp /home/$USERNAME/.ssh
echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
set_rights /home/$USERNAME/.ssh

# Force locale and keymap settings
locale-gen "$LOCALE_LANG"
localectl set-x11-keymap "$LOCALE_KEYMAP"
localectl set-keymap "$LOCALE_KEYMAP"

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

# Enable autologon for lightdm and sddm and if available, remove old sddm config
copy_and_parse_file "templates/75-htpcinit.conf" "/etc/lightdm/lightdm.conf.d/75-htpcinit.conf"
copy_and_parse_file "templates/75-htpcinit.conf" "/etc/sddm.conf.d/75-htpcinit.conf"
if [[ -f /etc/sddm.conf ]]; then
  rm /etc/sddm.conf
fi

# Set default wallpaper
copy_and_parse_file "templates/40-htpcinit-greeter.conf" "/etc/lightdm/lightdm-gtk-greeter.conf.d/40-htpcinit-greeter.conf"
sudo -u "$USERNAME" nitrogen --save --set-auto "$INSTALLATION/assets/$SCREEN_WALLPAPER"
cp "data/assets/$SCREEN_WALLPAPER" "/usr/share/kodi/media/splash.jpg"

# Enable steam controller support
copy_and_parse_file "templates/99-steam-controller-perms.rules" "/etc/udev/rules.d/99-steam-controller-perms.rules"

# Install lirc from source
# This can be done separatly with lirc.sh script

# Install lirc config
copy_and_parse_file "templates/lirc_options.conf" "/etc/lirc/lirc_options.conf"
copy_and_parse_file "templates/moncaso_312.lircd.conf" "/etc/lirc/lircd.conf.d/moncaso_312.lircd.conf"
systemctl restart lircd

# Configure graphics
if [[ "$(lspci -v | grep nvidia)" ]]; then
  apt-get install -y nvidia-driver-455 vdpauinfo
  nvidia-xconfig --no-use-edid-dpi
  sed -i "/DPI/d" /etc/X11/xorg.conf
  sed -i "/UseEdidDpi/i\
\    Option         \"DPI\" \"$SCREEN_DPI x $SCREEN_DPI\"" /etc/X11/xorg.conf
fi

# Configure sound
copy_and_parse_file "templates/.asoundrc" "/home/$USERNAME/.asoundrc"
#add_or_replace_line_in_file "/etc/pulse/default.pa" "load-module module-stream-restore" "load-module module-stream-restore restore_device=false"
#add_or_replace_line_in_file "/etc/pulse/default.pa" "load-module module-alsa-sink" "load-module module-alsa-sink device=hw:1,1" # 1,1 is detected from pactl list
#add_or_replace_line_in_file "/etc/pulse/default.pa" "set-default-sink" "set-default-sink 0"

# Configure Steam on virtualbox
#if [[ -z "$(lspci -v | grep nvidia)" ]]; then
#  STARTDIR=$(pwd)
#  cd /home/$USERNAME/.steam/ubuntu12_32/steam-runtime/i386/usr/lib/i386-linux-gnu
#  if [[ -f "libstdc++.so.6" ]]; then mv libstdc++.so.6 libstdc++.so.6.bak; fi
#  cd /home/$USERNAME/.steam/ubuntu12_32/steam-runtime/amd64/usr/lib/x86_64-linux-gnu
#  if [[ -f "libstdc++.so.6" ]]; then mv libstdc++.so.6 libstdc++.so.6.bak; fi
#  cd "$STARTDIR"
#fi

# Download and install chrome
if [[ -z $(which google-chrome) ]]; then
  wget -O /var/tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y /var/tmp/chrome.deb
fi

# Change GRUB config
sed -i "s/^GRUB_HIDDEN_/#GRUB_HIDDEN_/" /etc/default/grub
add_or_replace_line_in_file "/etc/default/grub" "GRUB_TIMEOUT=" "GRUB_TIMEOUT=$BOOT_TIMEOUT"
add_or_replace_line_in_file "/etc/default/grub" "GRUB_GFXMODE=" "GRUB_GFXMODE=${SCREEN_RESOLUTION}x32"
add_or_replace_line_in_file "/etc/default/grub" "GRUB_GFXPAYLOAD_LINUX=" "GRUB_GFXPAYLOAD_LINUX=keep"
#add_or_replace_line_in_file "/etc/default/grub" "GRUB_VIDEO_BACKEND=" "GRUB_VIDEO_BACKEND=vbe"
#copy_and_parse_file "templates/splash" "/etc/initramfs-tools/conf.d/splash"
update-initramfs -u
update-grub2

# Configure dvd/usb support (and cdrom lock)
dpkg-reconfigure libdvd-pkg
copy_and_parse_file "templates/50-cdromlock.conf" "/etc/sysctl.d/50-cdromlock.conf"
copy_and_parse_file "templates/82-cdrom.rules" "/etc/udev/rules.d/82-cdrom.rules"
copy_and_parse_file "templates/99-dvdlock" "/etc/pm/sleep.d/99-dvdlock"
chmod a+x "/etc/pm/sleep.d/99-dvdlock"
systemctl stop udisks2.service
systemctl mask udisks2.service
sysctl -p
udevadm control -R
udevadm trigger

# Mount NFS drives
add_nfs_mount "movies"
add_nfs_mount "series"
add_nfs_mount "music"
add_nfs_mount "pictures"
add_nfs_mount "phones"
#add_nfs_mount "games"
mount -a

# Basic configuration for kodi
KODI_USERDATA=/home/$USERNAME/.kodi/userdata
KODI_ADDONS=/home/$USERNAME/.kodi/addons
mkdir -p $KODI_USERDATA
mkdir -p $KODI_ADDONS
set_rights $KODI_USERDATA
set_rights $KODI_ADDONS
copy_and_parse_file "templates/advancedsettings.xml" "$KODI_USERDATA/advancedsettings.xml"
if [[ ! -f "$KODI_USERDATA/sources.xml" ]]; then
  copy_and_parse_file "templates/sources.xml" "$KODI_USERDATA/sources.xml"
fi
if [[ ! -f "$KODI_USERDATA/passwords.xml" ]]; then
  copy_and_parse_file "templates/passwords.xml" "$KODI_USERDATA/passwords.xml"
fi

# Kodi keybindings ?
copy_and_parse_file "templates/Lircmap.xml" "$KODI_USERDATA/Lircmap.xml"
copy_and_parse_file "templates/keymap_moncaso_312.xml" "$KODI_USERDATA/keymaps/keymap_moncaso_312.xml"

# Add additional files to the sources.xml
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Extras" "smb://$NAS_IP/Extras/"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Movies" "smb://$NAS_IP/Movies"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Series" "smb://$NAS_IP/Series"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Music" "smb://$NAS_IP/Music"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Pictures" "smb://$NAS_IP/Pictures"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Phones" "smb://$NAS_IP/Phones"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "files" "Skinbackup" "$KODI_USERDATA/addon_data/script.skin.helper.skinbackup"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "pictures" "Pictures" "smb://$NAS_IP/Pictures"
add_files_to_kodi_sources "$KODI_USERDATA/sources.xml" "pictures" "Phones" "smb://$NAS_IP/Phones"

# Add network credentials
add_samba_credential_to_kodi_passwords "$KODI_USERDATA/passwords.xml" "$NAS_IP" "$NAS_USERNAME" "$NAS_PASSWORD"
add_samba_credential_to_kodi_passwords "$KODI_USERDATA/passwords.xml" "$NAS_HOSTNAME" "$NAS_USERNAME" "$NAS_PASSWORD"

# Add addons
add_kodi_addon "repository.castagnait" "https://github.com/castagnait/repository.castagnait/raw/kodi/repository.castagnait-2.0.0.zip" # Netflix
add_kodi_addon "repository.supmagc" "https://github.com/supmagc/kodi-addons/raw/master/repository.supmagc/repository.supmagc-1.2.1.zip" # My own
add_kodi_addon "repository.emby.kodi" "http://kodi.emby.media/repository.emby.kodi-1.0.7.zip" # Emby
add_kodi_addon "repository.marcelveldt" "https://github.com/kodi-community-addons/repository.marcelveldt/raw/master/repository.marcelveldt-1.0.3.zip" # Old school addons
add_kodi_addon "repository.jurialmunkey" "https://github.com/jurialmunkey/repository.jurialmunkey/raw/master/repository.jurialmunkey-3.3.zip" # Arctic
add_kodi_addon "repository.zachmorris" "https://github.com/zach-morris/repository.zachmorris/releases/download/1.0.4/repository.zachmorris-1.0.4.zip" # Game internet archive
add_kodi_addon "repository.kodi_libretro_buildbot_game_addons" "https://github.com/zach-morris/kodi_libretro_buildbot_game_addons/raw/main/repository.kodi_libretro_buildbot_game_addons.zip" # Emulators
add_kodi_addon "repository.dobbelina" "https://dobbelina.github.io/repository.dobbelina-1.0.4.zip" # Cumincation
add_kodi_addon "script.cinemavision" "./install/script.cinemavision.zip" # cinemavision
add_kodi_addon "context.cinemavision" "./install/context.cinemavision.zip" # cinemavision

# Ensure correct permissions
set_rights /home/$USERNAME/.ssh

# Install plymouth theme
# apt-get install -y "./install/plymouth-theme-kodi-logo.deb"
#PWD=$(pwd)
#cd /tmp
#git clone https://github.com/supmagc/plymouth-theme-kodi-animated-logo.git
#cd plymouth-theme-kodi-animated-logo
#./build.sh
#dpkg -i plymouth-theme-kodi-animated-logo.deb
#cd ../
#rm -r plymouth-theme-kodi-animated-logo
#cd "$PWD"

# Install samba config and match password
copy_and_parse_file "templates/smb.conf" "/etc/samba/smb.conf"
echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -s -a $USERNAME
echo -e "$PASSWORD\n$PASSWORD" | passwd $USERNAME
systemctl restart nmbd.service

# Install wsd
#PWD=$(pwd)
#cd /tmp
#wget https://github.com/christgau/wsdd/archive/master.zip
#unzip master.zip
#mv wsdd-master/src/wsdd.py wsdd-master/src/wsdd
#cp wsdd-master/src/wsdd /usr/bin
#cp wsdd-master/etc/systemd/wsdd.service /etc/systemd/system
sed -i "s/Group=nobody/Group=nogroup/" /etc/systemd/system/wsdd.service
systemctl daemon-reload
systemctl enable wsdd
systemctl start wsdd
#cd "$PWD"

# Install nginx config
copy_and_parse_file "templates/nginx.conf" "/etc/nginx/conf.d/htpcinit.conf"
systemctl restart nginx.service

# Copy from backup
# rm -Rv /home/$USERNAME/Artwork/*
# rm -Rv /home/$USERNAME/Cinema/*
mkdir -p /home/$USERNAME/Artwork
mkdir -p /home/$USERNAME/Cinema
smbclient //$NAS_IP/Backup $NAS_PASSWORD -U=$NAS_USERNAME -c='prompt off;recurse on;cd HtpcInit\Artwork\;lcd /home/jelle/Artwork/;mget *'
smbclient //$NAS_IP/Backup $NAS_PASSWORD -U=$NAS_USERNAME -c='prompt off;recurse on;cd HtpcInit\Cinema\;lcd /home/jelle/Cinema/;mget *'
set_rights /home/$USERNAME/Artwork
set_rights /home/$USERNAME/Cinema

# Configure network
hostname "$HOSTNAME"
sed -i "/127.0.0.1/d" /etc/hosts
sed -i "1 i 127.0.0.1\t$HOSTNAME.$DOMAIN\t$HOSTNAME" /etc/hosts
sed -i "1 i 127.0.0.1\tlocalhost" /etc/hosts
resolvconf -u
nmcli connection modify "$NET_CONN" ipv4.method "manual" ipv4.dns "$NET_DNS" ipv4.addresses "$NET_IP" ipv4.gateway "$NET_GATE" ipv4.dns-search "$DOMAIN"
systemctl restart network-manager.service
