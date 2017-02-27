# This script prints the HTML pages of the Munin Gallery
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

@include "well-known-categories.incl"

BEGIN {
  lastcategory = ""
  lastnode = ""
  firstnode = "true"
  # Template will get filled with category and category description (%s)
  header = "\t<h2>Category :: %s (Core Collection)</h2>\n<p><big><em>%s</em></big></p>\t<ul class=\"groupview\">\n"

  nodeheader = "\t\t<li ><span class=\"domain\">%s</span>\n\t\t<ul>\n"
  nodefooter = "\t\t</ul>\n\t\t</li>\n"
  tmplplugin = "\t\t\t<li><span class=\"host\"><a href=\"https://raw.githubusercontent.com/munin-monitoring/munin/stable-2.0/plugins/%s\" title=\"Download\" class=\"download\"><img src=\"/static/img/download.gif\" alt=\"Download\"></a></span>&nbsp;<span class=\"host\"><a href=\"distro/svn/munin-stable-2.0/plugins/%s/%s.html\" title=\"Info\">%s</a></span></li>\n"
}

{
  # Column 1 of input file
  category = $1
  # Column 2 of input file
  pluginpath = $2

  # Split path into directory and plugin name
  if (match(pluginpath,"\/")) {
    nodedir = substr(pluginpath,1,RSTART-1)
    plugin = substr(pluginpath,RSTART+1)
    # cut off extension ".in"
    plugin = substr(plugin,1,length(plugin)-3)
  }

  # Next category
  if (category != lastcategory) {
    lastnode = ""
    # finish file of last category
    if (FNR != 1) {
      printf nodefooter "</ul>\n" >> fname
      system ("cat " scriptdir "/static/gallery-footer.html >> " fname) 
    }
    # create file for this category
    fname = htmldir "/" category "-index.html"
    system ("cp " scriptdir "/static/prep-index.html " fname)
    printf(header,category,arr[category]) >> fname
    lastcategory = category
    firstnode = "true"
  }

  # Next node
  if (nodedir != lastnode) {
    # finish section of last node
    if (firstnode == "false") {
      printf nodefooter >> fname
    }
    # start section of this node
    printf(nodeheader,nodedir) >> fname
    firstnode = "false"
    lastnode = nodedir
  }

  # Print plugin info
  printf(tmplplugin,pluginpath,nodedir,plugin,plugin) >> fname
  docfilename = workdir "/" nodedir "/" plugin ".html"
  cmd = "test -f " docfilename
  rc = system(cmd)
  if (rc!=0) {
    cmd = "perldoc -o html -d " docfilename " " workdir "/" pluginpath " 2>&1"
    result = system(cmd)

    # On error put "Oops" page in place
    if (result > 0) {
      cmd = "cp " scriptdir "/static/leer.html " workdir "/" nodedir "/" plugin ".html 2>&1"
      system(cmd)
    } else {
      # Add stylesheet to head
      cmd2 = "sed -i 's#</head>#<link rel=\"stylesheet\" href=\"\/static\/css\/style-doc.css\" /></head>#g' " docfilename
      system(cmd2)
    }
  }
}

END {
  # Finish file for last node
  printf nodefooter "</ul>\n" >> fname
  system ("cat " scriptdir "/static/gallery-footer.html >> " fname) 
}
