#!/bin/bash
#
# This script builds a HTML presentation of the perldocs 
# integrated in the Munin plugins collected at github
# so that users can browse info about available plugins
#
# In this stage we address the plugins from the Munin Distribution 2.0.
# https://github.com/munin-monitoring/munin/tree/stable-2.0/plugins
#
# As these have file endings ".in" we have to maintain
# a separate build script.
# 
# Plugin authors shall contribute example graphs
# for their plugins also. Rules are defined here:
# http://munin-monitoring.org/wiki/PluginGallery
#
# Author: Gabriele Pohl (contact@dipohl.de)
# Date: 2014-09-07
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE as published
# by the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# You should have received a copy of the GNU AFFERO GENERAL PUBLIC LICENSE
# (for example COPYING); If not, see <http://www.gnu.org/licenses/>.
#

# to set ownership of the Gallery files
# WWWUSER=gap
# WWWGROUP=apache

# DocumentRoot of the Gallery
HTMLDIR=/var/www/html/munin-gallery

# source for which the Gallery should be build
REPO=munin
BRANCH=stable-2.0

# SVN cannot clone github branch "stable-2.0"
# at least I found no way to do it..
# As a workaround I'll use a zip download.
SVNROOTDIR=$HTMLDIR/distro/svn

# Directory within DocumentRoot to store pages and images about the plugins
WORKDIR=$SVNROOTDIR/$REPO-$BRANCH/plugins

# This directory is for files only needed to build the Gallery
SCRIPTDIR=/home/gap/projects/munin/github/munin/contrib/plugin-gallery

# Start protocol
echo "
================================
Building Munin Plugin Gallery for repo $REPO (branch $BRANCH)

Your presets:

SVNROOTDIR: $SVNROOTDIR
HTMLDIR: $HTMLDIR
WORKDIR: $WORKDIR
"

# Check existence of SVNROOTDIR
if (! test -d "$SVNROOTDIR") then
    echo "ERROR: Directory for github download not found! Please create it here: $SVNROOTDIR"
    exit;
fi

echo "Preparations..
..cleaning data of the last run"

if (test -d "$WORKDIR") then

   echo "..empty workdir"
   rm -rf $WORKDIR

   # This method is only relevant, if we
   # use svn or git to update local repo
   # At the time we remove *everything* and extract a fresh zipfile
   #   # Remove all POD generated plugin pages from the last run
   #   find $WORKDIR -name *.html -exec rm {} \;

fi

echo "..remove existing Gallery pages"
rm -rf $HTMLDIR/*.html

echo "..remove existing zip download file"
rm $SVNROOTDIR/$BRANCH.zip

echo "..get a fresh zip file from github repo"
wget --no-verbose --output-document=$SVNROOTDIR/$BRANCH.zip https://github.com/munin-monitoring/$REPO/archive/$BRANCH.zip 
unzip -q -d $SVNROOTDIR $SVNROOTDIR/$BRANCH.zip $REPO-$BRANCH/plugins/*

echo "..cp list of well-known-categories to WORKDIR"
cp $SCRIPTDIR/well-known-categories.incl $WORKDIR

cd $WORKDIR
echo "
Start building the new gallery pages.."

# Find relation between plugins and categories
grep -iR --exclude-from=$SCRIPTDIR/grep-files.excl category node.* | grep -v .svn | sort -u > $SCRIPTDIR/cat.lst
awk -F : -f $SCRIPTDIR/split-greplist.awk $SCRIPTDIR/cat.lst | LC_COLLATE=C sort -u > $SCRIPTDIR/catsorted.lst

# Create categories navigation snippet to integrate in each page
awk -f $SCRIPTDIR/prep-catnav.awk -v scriptdir=$SCRIPTDIR $SCRIPTDIR/catsorted.lst | sort >$SCRIPTDIR/cat-plugins.lst

# Compile template for category pages
cat $SCRIPTDIR/static/gallery-header.html $SCRIPTDIR/static/gallery-cat-header.html $SCRIPTDIR/static/gallery-catnav.html $SCRIPTDIR/static/gallery-cat-footer.html >$SCRIPTDIR/static/prep-index.html

# Create entry page
cat $SCRIPTDIR/static/gallery-header.html $SCRIPTDIR/static/gallery-cat-header.html $SCRIPTDIR/static/gallery-catnav.html $SCRIPTDIR/static/gallery-cat-footer.html $SCRIPTDIR/static/gallery-intro.html $SCRIPTDIR/static/gallery-footer.html >$HTMLDIR/index.html

# Create Gallery pages for all categories that were explicitly set in the plugin script files
awk -f $SCRIPTDIR/print-gallery.awk -v scriptdir=$SCRIPTDIR workdir=$WORKDIR htmldir=$HTMLDIR $SCRIPTDIR/catsorted.lst >$SCRIPTDIR/print-gallery1.log

# Find the plugins that fell thru the sieve..
find node.* -name '*.in' | grep -v node.d.debug | sort > $SCRIPTDIR/all-plugins.lst
diff $SCRIPTDIR/cat-plugins.lst $SCRIPTDIR/all-plugins.lst | grep '^>' >$SCRIPTDIR/nocat-plugins.lst

# Push plugins with no category to "other"
sed -i 's/>/other/g' $SCRIPTDIR/nocat-plugins.lst
grep ^other $SCRIPTDIR/catsorted.lst >>$SCRIPTDIR/nocat-plugins.lst
LC_COLLATE=C sort -u $SCRIPTDIR/nocat-plugins.lst > $SCRIPTDIR/other-plugins.lst

# Create Gallery pages for category "other"
awk -f $SCRIPTDIR/print-gallery.awk -v scriptdir=$SCRIPTDIR workdir=$WORKDIR htmldir=$HTMLDIR $SCRIPTDIR/other-plugins.lst >$SCRIPTDIR/print-gallery2.log

# Collect example graphs
find node.* -name '*.png' | grep -v node.d.debug | sort > $SCRIPTDIR/example-graphs.lst

# Include example graphs in perldoc pages
awk -f $SCRIPTDIR/include-graphs.awk -v workdir=$WORKDIR $SCRIPTDIR/example-graphs.lst >$SCRIPTDIR/include-graphs.log

# chown -R $WWWUSER.$WWWGROUP $HTMLDIR
chmod -R a+rx $HTMLDIR

# Some statistic
echo "
STATISTICS
----------"
echo `cat $SCRIPTDIR/nocat-plugins.lst | wc -l` "plugins without category were assigned to category 'other'"
echo `grep "output saved" $SCRIPTDIR/print-gallery?.log | wc -l` "times created perldoc pages with content"
echo `grep "No documentation" $SCRIPTDIR/print-gallery?.log | wc -l` "times no perldoc content found"
echo `cat $SCRIPTDIR/example-graphs.lst | wc -l` "example graph images illustrate the plugin pages"

# End protocol
echo "================================"
