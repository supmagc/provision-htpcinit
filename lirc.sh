#!/bin/bash

sudo apt-get install autoconf automake libtool build-essential python3 python3-dev python3-setuptools kmod pkg-config xsltproc linux-headers-$(uname -r) libsystemd-dev

git clone https://github.com/supmagc/lirc-mplay.git
cd lirc-mplay/

./autogen.sh
./configure --with-x --with-driver="mplay2" --prefix=""

make
# Sometimes, a doc file is symlinked
git status | grep typechange | awk '{print $2}' | xargs git checkout
sudo make install

sudo systemctl enable lircd

cd ../
rm -R lirc-mplay
