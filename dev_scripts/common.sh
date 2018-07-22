#!/bin/bash

BASEDIR=$(readlink -f -- "$FINDBIN/..")
DESTDIR="$BASEDIR/sandbox"
PERLLIB=$DESTDIR$(perl -V:sitelib | cut -d"'" -f2)


cd $BASEDIR

