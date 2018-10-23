#!/bin/sh
#
# verify that plugins are installed and published by munin-node
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


test_expect_success "request list of configured plugins" '
  printf "%s\\n" list quit | nc localhost munin | grep -v "^#" >all_plugins
  # ignore non-predictable names (e.g. related to the network interfaces of the environment)
  for a in $(sed "s/ if_\\w\\+//g" <all_plugins); do echo "$a"; done >all_without_network_interfaces
  printf "%s\n" cpu df df_inode entropy forks fw_packets interrupts \
    irqstats load memory netstat open_files open_inodes proc_pri \
    processes swap threads uptime users vmstat \
    >expected_plugins
  # show diff in case of failure (can be removed after https://github.com/chriscool/sharness/issues/14)
  test_cmp all_without_network_interfaces expected_plugins
'

test_done
