#! /bin/sh

# Be pedantic
set -x
set -e

# install deps
sudo apt-get install libpango1.0-dev libxml2-dev

# Download a fixed version
wget http://oss.oetiker.ch/rrdtool/pub/rrdtool-1.4.8.tar.gz
tar -xzvf rrdtool-1.4.8
cd rrdtool-1.4.8 && ./configure --prefix=/usr && make && make install
