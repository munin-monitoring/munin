# This script includes the example graph images 
# into the HTML pages of the Munin Gallery
#
# $Id$
# Author: Gabriele Pohl (contact@dipohl.de)
# Date: 2014-09-03
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
  FS = "/" 
  lengraphdir = length("example-graphs")
  lastplugin = ""
  lastdir= ""
  pattern= ">NAME</a></h1>"
  preheader = ">NAME\\</a>\\</h1>\\<h2>\\<a class=\"u\" name=\"example-graphs\">"
  postheader = "\\</a>\\</h2>\\<p>"
  footer = "\\<\\/p>"
}

{
  # Last Column of input file
  graphfile = $(NF)
  # Path to the plugin
  plugindir = substr($0,1,length($0) - length(graphfile) - lengraphdir - 1 )

  # Pick plugin name out of graph file name
  if (match(graphfile,"-")) {
    plugin = substr(graphfile,1,RSTART-1)
    print "Plugin = " plugindir plugin "\n"
  }

  # Next plugin
  if (plugin != lastplugin) {
    # finish snippet of last plugin
    if (FNR != 1) {
      inc = inc footer
      cmd = "sed -i 's:" pattern ":" inc ":I' " workdir "/" lastdir lastplugin ".html"
      system (cmd)
    }
    # create snippet for next plugin file
    inc = preheader plugin postheader
    lastplugin = plugin
    lastdir = plugindir
  }

  # Print graph include code
  inc = inc "\\<img src=\"example-graphs/" graphfile "\" alt=\"Example Graph\"> "
}

END { 
      inc = inc footer
      cmd = "sed -i 's:" pattern ":" inc ":I' " workdir "/" lastdir lastplugin ".html"
      system (cmd)
}
