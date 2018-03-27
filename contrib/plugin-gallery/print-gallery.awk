# This script prints the HTML pages of the Munin Gallery
#
# Input:
#   First Column: category
#   Second Column: plugin filename (BEWARE: without a leading "./")
# The input lines are sorted by category.
#
# Author: Gabriele Pohl (contact@dipohl.de)
# Date: 2014-08-23
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE as published
# by the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# You should have received a copy of the GNU AFFERO GENERAL PUBLIC LICENSE
# (for example COPYING); If not, see <http://www.gnu.org/licenses/>.
#

BEGIN {
  previous_category = ""
  previous_node_dir = ""
  first_node = "true"
  # Template will get filled with category and category description (%s)
  header = "\t<h2>Category :: %s (" collection_name ")</h2>\n<p><big><em>%s</em></big></p>\t<ul class=\"groupview\">\n"

  nodeheader = "\t\t<li ><span class=\"domain\">%s</span>\n\t\t<ul>\n"
  nodefooter = "\t\t</ul>\n\t\t</li>\n"
  tmplplugin = "\t\t\t<li><span class=\"host\"><a href=\"" plugins_source_url "/%s\" title=\"Download\" class=\"download\"><img src=\"/static/img/download.gif\" alt=\"Download\"></a></span>&nbsp;<span class=\"host\"><a href=\"" publish_path "%s/%s.html\" title=\"Info\">%s</a></span></li>\n"

  # translation table for common plugin directory names
  node_dir_map["node.d"] = "All Platforms"
  node_dir_map["node.d.aix"] = "Platform AIX"
  node_dir_map["node.d.cygwin"] = "Platform Cygwin"
  node_dir_map["node.d.darwin"] = "Platform Darwin / MacOS"
  node_dir_map["node.d.freebsd"] = "Platform FreeBSD"
  node_dir_map["node.d.hp-ux"] = "Platform HP-UX"
  node_dir_map["node.d.java"] = "Platform Java"
  node_dir_map["node.d.linux"] = "Platform Linux"
  node_dir_map["node.d.netbsd"] = "Platform NetBSD"
  node_dir_map["node.d.openbsd"] = "Platform OpenBSD"
  node_dir_map["node.d.sunos"] = "Platform SunOS / Solaris"
}

{
  # Column 1 of input file
  category = $1
  # Column 2 of input file
  pluginpath = $2

  # Split path into directory and plugin name
  if (match(pluginpath, "/")) {
    node_dir = substr(pluginpath, 1, RSTART - 1)
    plugin = substr(pluginpath, RSTART + 1)
    if (match(pluginpath, "\\.in$")) {
      # cut off extension ".in" (for stable-2.0 branch)
      plugin = substr(plugin, 1, length(plugin) - 3)
    }
  }

  # Next category
  if (category != previous_category) {
    previous_node_dir = ""
    # finish file of last category
    if (FNR != 1) {
      printf nodefooter "</ul>\n" >> fname
      system("cat " static_dir "/gallery-footer.html >> " fname)
    }
    # create file for this category
    fname = target_dir publish_path category "-index.html"
    system("mkdir -p '" target_dir publish_path "'")
    system("cp '" prep_index_file "' '" fname "'")
    printf(header, category, arr[category]) >> fname
    previous_category = category
    first_node = "true"
  }

  # Next node
  if (node_dir != previous_node_dir) {
    # finish section of last node
    if (first_node == "false") {
      printf nodefooter >> fname
    }
    # start section of this node
    if (node_dir_map[node_dir] != "") {
      platform = node_dir_map[node_dir]
    } else {
      platform = node_dir
    }
    printf(nodeheader, platform) >> fname
    first_node = "false"
    previous_node_dir = node_dir
  }

  # Print plugin info
  printf(tmplplugin, pluginpath, node_dir, plugin, plugin) >> fname
  docfilename = target_dir publish_path node_dir "/" plugin ".html"
  cmd = "test -f " docfilename
  rc = system(cmd)
  if (rc != 0) {
    this_dirname = gensub("/?[^/]*/?$", "", 1, target_dir publish_path node_dir "/" plugin)
    if (this_dirname != "") system("mkdir -p '" this_dirname "'")
    cmd = "perldoc -o html -d " docfilename " " plugin_dir "/" pluginpath " 2>&1"
    result = system(cmd)

    # On error put "Oops" page in place
    if (result > 0) {
      cmd = "cp '" static_dir "/leer.html' '" target_dir publish_path node_dir "/" plugin ".html'"
    } else {
      # Add stylesheet to head
      cmd = "sed -i 's#</head>#<link rel=\"stylesheet\" href=\"/static/css/style-doc.css\" /></head>#g' " docfilename
    }
    result = system(cmd)
    if (result > 0) exit 1
  }
}

END {
  # Finish file for last node
  printf nodefooter "</ul>\n" >> fname
  system ("cat " static_dir "/gallery-footer.html >> " fname)
}
