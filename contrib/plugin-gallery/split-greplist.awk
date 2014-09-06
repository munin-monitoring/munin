# This script tries to find the relation 
# between plugin and category.
#
# INPUT
# It is fed with grep search for term 'category'
# in the plugin script files
# 
# OUTPUT
# Column1 category
# Column2 path to plugin file relative to github directory "plugin"
#
# ASSUMPTION
# Category is always only _one_ word
# @plugin-authors: Use underscore to substitute blanks
#
# $Id: split-greplist.awk,v 1.3 2014/08/24 10:03:00 gap Exp gap $
# Author: Gabriele Pohl (contact@dipohl.de)
# Date: 2014-08-24
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE as published
# by the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# You should have received a copy of the GNU AFFERO GENERAL PUBLIC LICENSE
# (for example COPYING); If not, see <http://www.gnu.org/licenses/>.
#

function Trim(string) {
    sub(/=>/, "", string)
    gsub(/\"/, "", string)
    gsub(/'/, "", string)
    sub(/^[[:space:]]/, "", string)
    sub(/[[:space:]]+/, "", string)
    return string
}

function GrabAlphaNum(string) {
  strout = ""

  for (i=1; i<=length(string); i++) {
    lettr = substr(string,i,1);
    if (match(lettr,"([[:alnum:]]|\-|\_)")) 
      strout = strout lettr
    else 
      break;
  }
  return strout;
}


BEGIN {}

{
    plugin = $1
    if (match(plugin, "node.d.debug")) next;
    if (match($2, "graph_category.*")) {
      # RSTART is where the pattern starts
      category = substr($2,RSTART+15)
      category = Trim(category)
      category = GrabAlphaNum(category)
      if (length(category) < 1) category = "other"
      printf("%s %s\n", tolower(category), plugin)
      next
    }
    if (match($2, "category.*=>.*")) {
      # RSTART is where the pattern starts
      category = substr($2,RSTART+9)
      category = Trim(category)
      category = GrabAlphaNum(category)
      if (length(category) < 1) category = "other"
      printf("%s %s\n", tolower(category), plugin)
    }
}

END {}

