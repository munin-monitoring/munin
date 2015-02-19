#!/bin/bash

FINDBIN=$(cd -- "$(dirname "$0")" && pwd)
BASEDIR="$(cd "$FINDBIN/.." && pwd -P)"
DESTDIR="$BASEDIR/sandbox"
FINDDIR="$BASEDIR/sandbox $BASEDIR/contrib"
PERLSITELIB=$(perl -V:sitelib | cut -d"'" -f2)


cd $BASEDIR

