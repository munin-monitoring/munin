# This script tries to find the relation
# between plugin and category.
#
# INPUT
# It is fed with grep search for term 'category' or for plugin-specifc strings
# (e.g. "Munin::Plugin::Pgsql"). in the plugin script files.
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


function GrabAlphaNum(string) {
  strout = ""

  for (i=1; i<=length(string); i++) {
    lettr = substr(string, i, 1)
    if (match(lettr, "([[:alnum:]]|_|-)"))
      strout = strout lettr
    else
      break
  }
  return strout
}


{
    plugin = $1
    if (match(plugin, "node.d.debug")) next

    # Colon used as field separator, but as it
    # can also be used as separator for subcategories,
    # we have to fetch the whole right side from $0
    category_line_text = substr($0, length($1)+2)

    if (category_line_text ~ /Munin::Plugin::Pgsql/) {
      # plugins using the "Munin::Plugin::Pgsql" do not contain an explicit "category" line
      category = "db"
    } else if (match(category_line_text, "env\\.")) {
      # some lines like "env.category" can be mistaken
      next
    } else if (match(category_line_text, "category[^a-z]*\\$")) {
      # this looks like the name of a variable is following
      next
    } else if (match(category_line_text, "^\\s*#") && !match(category_line_text, "graph_category")) {
      # this looks like a comment (but no "human override")
      next
    } else if (match(category_line_text, "/category/")) {
      # this menu item label is used in "http-response-times"
      next
    } else if (match(category_line_text, "(label|documentation).*category") && !match(category_line_text, "\\\\n.*\\\\n")) {
      # This looks like a verbal description (e.g. 'graph_vlabel').
      # But we want to ignore multi-line text (see plugins/node.d/ipmi_).
      next
    } else if (match(category_line_text, "\\<the\\>")) {
      # this looks like a verbal description
      next
    } else if (match(category_line_text, "filterwarnings\\(")) {
      # this looks like a python "warnings" configuration (see percona/percona_)
      next
    } else if (match(category_line_text, "category queries \\{")) {
      # this string is used in the "bind9" plugin (bind configuration syntax)
      next
    } else if (match(tolower(category_line_text), "select.*from.*(join|where)")) {
      # this looks like the name of a variable is following
      next
    } else if (match(category_line_text, "[^$]category\\W")) {
      # Either hash assignments ("=>"), generic variable assignments, python dictionaries or simple
      # print/echo statements are matched.
      if (match(category_line_text, "graph_category\\W")) {
        category = gensub("^.*graph_category\\W+", "", 1, category_line_text)
      } else {
        category = gensub("^.*[^$]category\\W+", "", 1, category_line_text)
      }
    } else {
      next
    }
    category = GrabAlphaNum(category)
    if (length(category) >= 1) printf("%s %s\n", tolower(category), plugin)
}
