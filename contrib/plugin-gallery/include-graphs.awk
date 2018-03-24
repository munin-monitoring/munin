# This script includes the example graph images
# into the HTML pages of the Munin Gallery
#
# Author: Gabriele Pohl (contact@dipohl.de)
# Date: 2014-08-30
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
  graph_subdir = "example-graphs"
  previous_node = ""
  previous_plugin_basename = ""
  previous_plugin_dir = ""
  pattern = ">NAME</a></h1>"
  preheader = ">NAME\\</a>\\</h1>\\<h2>\\<a class=\"u\" name=\"" graph_subdir "\">"
  postheader = "\\</a>\\</h2>\\<p>"
  footer = "\\<\\/p>"

}

function write_example_graph_links_to_plugin_html(plugin_basename, graph_basename, filename, inc) {
  if (plugin_basename != "") {
    inc = inc footer
    if (system("sed -i 's:" pattern ":" inc ":I' '" filename "'") > 0) {
      print "ERROR: Failed to update reference for '" graph_basename "': possibly invalid filename pattern (expected '" graph_subdir "/PLUGIN-SOMETHING.png')?" > "/dev/stderr"
    }
  }
}

{
  # Last Column (slash-separated) of input file
  graph_basename = $(NF)

  if ($(NF-1) != graph_subdir) {
    # the path of the example graph looks invalid
    print("Misplaced: " $0)
  } else {
    # Path to the plugin
    plugin_dir = substr($0, 1, length($0) - length(graph_basename) - length(graph_subdir) - 1 )

    # Pick plugin name out of graph file name
    if (match(graph_basename, "-")) {
      plugin_basename = substr(graph_basename, 1, RSTART - 1)
      print("Plugin: " node "/" plugin_basename)
    }

    # Next plugin
    if (plugin_basename != previous_plugin_basename) {
      # finish snippet of previous plugin
      write_example_graph_links_to_plugin_html(previous_plugin_basename, graph_basename,
          target_dir "/" previous_plugin_dir "/" previous_node "/" previous_plugin_basename ".html", inc);
      # create snippet for next plugin file
      inc = preheader plugin_basename postheader
      previous_plugin_basename = plugin_basename
      previous_plugin_dir = plugin_dir
      previous_node = node
    }

    # Print graph include code
    inc = inc "\\<img src=\"" graph_subdir "/" graph_basename "\" alt=\"Example Graph\"> "
  }
}

END {
  write_example_graph_links_to_plugin_html(plugin_basename, graph_basename,
      target_dir "/" plugin_dir "/" node "/" plugin_basename ".html", inc);
}
