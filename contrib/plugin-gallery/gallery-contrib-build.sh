#!/bin/bash
#
# This script builds a HTML presentation of the perldocs 
# integrated in the Munin plugins collected at github
# so that users can browse info about available plugins
#
# Here we treat the 3rd party plugins contributed 
# via github https://github.com/munin-monitoring/contrib
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

# Directory within DocumentRoot to store pages and images about the plugins
WORKDIR=$HTMLDIR/contrib/plugins

# This directory is for files only needed to build the Gallery
SCRIPTDIR=/home/gap/projects/munin/github/munin/contrib/plugin-gallery

# Remove POD pages of last run
find $WORKDIR -name *.html -exec rm {} \;

# Download github files
if test -d "$WORKDIR/.svn"; then
  cd $WORKDIR 
  svn update --accept theirs-full
else
  svn checkout https://github.com/munin-monitoring/contrib/trunk/plugins $WORKDIR
  # We want a relative path as output of find and grep
  cd $WORKDIR 
fi

# Find relation between plugins and categories
grep -iR --exclude-from=$SCRIPTDIR/grep-files-contrib.excl graph_category * | sort -u > $SCRIPTDIR/cat-contrib.lst
awk -F : -f $SCRIPTDIR/split-greplist.awk $SCRIPTDIR/cat-contrib.lst | LC_COLLATE=C sort -u > $SCRIPTDIR/catsorted-contrib.lst

# Create categories navigation snippet to integrate in each page
awk -f $SCRIPTDIR/prep-catnav-contrib.awk -v scriptdir=$SCRIPTDIR $SCRIPTDIR/catsorted-contrib.lst | sort >$SCRIPTDIR/cat-plugins-contrib.lst

# Compile template for category pages
cat $SCRIPTDIR/static/gallery-header.html $SCRIPTDIR/static/gallery-cat-header.html $SCRIPTDIR/static/gallery-catnav-contrib.html $SCRIPTDIR/static/gallery-cat-footer.html >$SCRIPTDIR/static/prep-index-contrib.html

# Create entry page
cat $SCRIPTDIR/static/gallery-header.html $SCRIPTDIR/static/gallery-cat-header.html $SCRIPTDIR/static/gallery-catnav-contrib.html $SCRIPTDIR/static/gallery-cat-footer.html $SCRIPTDIR/static/gallery-intro.html $SCRIPTDIR/static/gallery-footer.html >$HTMLDIR/contrib/index.html

# Create Gallery pages for all categories that were explicitly set in the plugin script files
awk -f $SCRIPTDIR/print-gallery-contrib.awk -v scriptdir=$SCRIPTDIR workdir=$WORKDIR htmldir=$HTMLDIR $SCRIPTDIR/catsorted-contrib.lst >$SCRIPTDIR/print-gallery1-contrib.log

# Find the plugins that fell thru the sieve..
find . -type f | grep -v .html | grep -v .svn | grep -v .png | grep -v .txt | grep -v .rst | grep -v .ini | grep -v .conf | grep -v README | grep -v .git | awk '{print substr($0,3)}' |sort > $SCRIPTDIR/all-plugins-contrib.lst
diff $SCRIPTDIR/cat-plugins-contrib.lst $SCRIPTDIR/all-plugins-contrib.lst | grep '^>' >$SCRIPTDIR/nocat-plugins-contrib.lst

# Push plugins with no category to "other"
sed -i 's/>/other/g' $SCRIPTDIR/nocat-plugins-contrib.lst
grep ^other $SCRIPTDIR/catsorted-contrib.lst >>$SCRIPTDIR/nocat-plugins-contrib.lst
LC_COLLATE=C sort -u $SCRIPTDIR/nocat-plugins-contrib.lst > $SCRIPTDIR/other-plugins-contrib.lst

# Create Gallery pages for category "other"
awk -f $SCRIPTDIR/print-gallery-contrib.awk -v scriptdir=$SCRIPTDIR workdir=$WORKDIR htmldir=$HTMLDIR $SCRIPTDIR/other-plugins-contrib.lst >$SCRIPTDIR/print-gallery2-contrib.log

# Collect example graphs
find . -name '*.png' | grep example-graphs |  awk '{print substr($0,3)}' | sort > $SCRIPTDIR/example-graphs-contrib.lst

# Include example graphs in perldoc pages
awk -f $SCRIPTDIR/include-graphs-contrib.awk -v workdir=$WORKDIR $SCRIPTDIR/example-graphs-contrib.lst >$SCRIPTDIR/include-graphs-contrib.log

# chown -R $WWWUSER.$WWWGROUP $HTMLDIR
chmod -R a+rx $HTMLDIR

# Some statistic
echo `cat $SCRIPTDIR/nocat-plugins-contrib.lst | wc -l` "plugins without category were assigned to category 'other'"
echo `grep "output saved" $SCRIPTDIR/print-gallery*-contrib.log | wc -l` "times created perldoc pages with content"
echo `grep "No documentation" $SCRIPTDIR/print-gallery*-contrib.log | wc -l` "times no perldoc content found"
echo `cat $SCRIPTDIR/example-graphs-contrib.lst | wc -l` "example graph images illustrate the plugin pages"
