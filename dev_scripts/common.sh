#!/bin/sh

BASEDIR=$(readlink -f -- "$FINDBIN/..")
DESTDIR="$BASEDIR/sandbox"
# shellcheck disable=SC2034
PERLLIB=$DESTDIR$(perl -V:sitelib | cut -d"'" -f2)


cd "$BASEDIR"
