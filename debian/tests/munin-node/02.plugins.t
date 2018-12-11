#!/bin/sh
#
# verify that plugins are installed and published by munin-node
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


test_expect_success "request list of configured plugins" '
  # Retrieve all plugins (a single line with space separated names) and split it into multiple
  # lines, each containing one plugin name.
  # Announce the multigraph capability - otherwise only trivial plugins are returned.
  printf "%s\\n" "cap multigraph" "list" "quit" | nc localhost munin | grep -vE "^(#|cap )" | xargs -n 1 echo | sort >all_plugins
  # ignore non-predictable names (e.g. related to the network interfaces of the environment)
  grep -v "^if_" all_plugins | sort >all_without_network_interfaces
  {
    # most plugins work without requirements - we can assume they are available
    cat <<EOF
df
df_inode
diskstats
irqstats
memory
proc_pri
processes
procfs
procsys
threads
users
vmstat
EOF
  } | sort >expected_plugins
  test_cmp expected_plugins all_without_network_interfaces
'

test_done
