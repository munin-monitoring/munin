#!/bin/bash

BASEDIR=$(readlink -f -- "$FINDBIN/..")
DESTDIR="$BASEDIR/root"
PERLSITELIB=$(perl -V:sitelib | cut -d"'" -f2)

cd $BASEDIR

