#!/bin/bash

sudo apt-get install autoconf automake libtool build-essential python3 python3-dev python3-setuptools kmod pkg-config xsltproc linux-headers-$(uname -r)

git clone https://github.com/supmagc/lirc-mplay.git
cd lirc-mplay/

./autogen.sh
./configure --with-x --with-driver="mplay2" --prefix=""

make
sudo make install

cd ../
rm -R lirc-mplay
