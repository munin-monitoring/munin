#!/bin/sh
#
# verify that plugins are installed and published by munin-node
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


test_expect_success "request list of configured plugins" '
  # Retrieve all plugins (a single line with space separated names) and split it into multiple
  # lines, each containing one plugin name.
  printf "%s\\n" list quit | nc localhost munin | grep -v "^#" | xargs -n 1 echo | sort >all_plugins
  # ignore non-predictable names (e.g. related to the network interfaces of the environment)
  grep -v "^if_" all_plugins | sort >all_without_network_interfaces
  {
    # most plugins work without requirements - we can assume they are available
    cat <<EOF
cpu
df
df_inode
entropy
forks
fw_packets
interrupts
irqstats
load
memory
netstat
open_files
open_inodes
proc_pri
processes
swap
threads
uptime
users
vmstat
EOF
    # some plugins are only installed if specific programs are available in the test environment
    if [ -x /usr/sbin/conntrack ]; then
      echo fw_conntrack
      echo fw_forwarded_local
    fi
  } | sort >expected_plugins
  test_cmp expected_plugins all_without_network_interfaces
'

test_done
