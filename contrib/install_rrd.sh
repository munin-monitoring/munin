#! /bin/sh

# Be pedantic
set -x
set -e

# We want to optimize for *compile time*
export CFLAGS="-O0 -pipe"

# install deps
sudo apt-get install libpango1.0-dev libxml2-dev

# Download a fixed version
wget http://oss.oetiker.ch/rrdtool/pub/rrdtool-1.4.8.tar.gz
tar -xzvf rrdtool-1.4.8.tar.gz
cd rrdtool-1.4.8

./configure \
	--disable-dependency-tracking \
	--disable-rrdcgi \
	--disable-mmap \
	--disable-pthread \
	--enable-perl \
	--enable-perl-site-install \
	--disable-ruby \
	--disable-lua \
	--disable-tcl \
	--disable-python \
	--disable-libdbi \
	--disable-libwrap \
	# Leave at the end

make
sudo make install

# Test the install
perl -MRRDs -e ''
