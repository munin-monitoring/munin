#!/bin/bash

BASEDIR=$(readlink -f -- "$FINDBIN/..")
DESTDIR="$BASEDIR/sandbox"
PERLSITELIB=$(perl -V:sitelib | cut -d"'" -f2)


cd $BASEDIR

