#!/bin/sh
#
# verify that plugins are installed and published by munin-node
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


test_expect_success "request list of configured plugins" '
  all_plugins=$(printf "%s\\n" list quit | nc localhost munin | grep -v "^#")
  # ignore non-predictable names (e.g. related to the network interfaces of the environment)
  all_without_network_interfaces=$(echo "$all_plugins" | sed "s/ if_\\w\\+//g")
  [ "$all_without_network_interfaces" = "cpu df df_inode entropy forks fw_packets interrupts irqstats load memory netstat open_files open_inodes proc_pri processes swap threads uptime users vmstat" ]
'

test_done
