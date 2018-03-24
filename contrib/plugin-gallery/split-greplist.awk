# This script tries to find the relation
# between plugin and category.
#
# INPUT
# It is fed with grep search for term 'category'
# in the plugin script files
#
# OUTPUT
# First Column: string with category
# Second Column: path to plugin file relative to github directory "plugin"
#
# ASSUMPTION
# Category is always only _one_ word
# @plugin-authors: Use underscore to substitute blanks
#
# Testing:
#    find plugins -type f -executable | xargs grep -H category | awk -F : -f THIS_FILE
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

function Trim(string) {
    sub(/=>/, "", string)
    sub(/=/, "", string)
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
    if (match(lettr, "([[:alnum:]]|_|:|-)"))
      strout = strout lettr
    else
      break;
  }
  return strout;
}


{
    plugin = $1
    if (match(plugin, "node.d.debug")) next
    # Colon used as field separator, but as it
    # can also be used as separator for subcategories,
    # we have to fetch the whole right side from $0
    grepstr = substr($0, length($1)+2)
    if (match(grepstr, "graph_category.*")) {
      # RSTART is where the pattern starts
      category = substr(grepstr, RSTART + 15)
    } else if (match(grepstr, "category.*=>.*")) {
      # RSTART is where the pattern starts
      category = substr(grepstr, RSTART + 9)
    } else {
      next
    }
    category = Trim(category)
    category = GrabAlphaNum(category)
    if (length(category) < 1) category = "other"
    printf("%s %s\n", tolower(category), plugin)
}
