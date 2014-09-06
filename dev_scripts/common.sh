#!/bin/bash

BASEDIR="$(cd "$FINDBIN/.." && pwd -P)"
DESTDIR="$BASEDIR/sandbox"
FINDDIR="$BASEDIR/sandbox $BASEDIR/contrib"
PERLSITELIB=$(perl -V:sitelib | cut -d"'" -f2)


cd $BASEDIR

