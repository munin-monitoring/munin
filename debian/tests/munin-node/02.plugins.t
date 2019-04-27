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
    # Some plugins are only installed if the test environment fulfills the conditions specified in
    # their "autoconf" section. Thus the conditions below are a copy of the "autoconf" conditions
    # of the affected plugins.
    if [ -n "$(find /sys/class/thermal/ -maxdepth 1 -name "thermal_zone*" 2>/dev/null || true)" ]; then
      echo acpi
    fi
    if [ -e "/sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state" ] || [ -e "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq" ]; then
      echo cpuspeed
    fi
    if [ -x /usr/sbin/conntrack ] || [ -e /proc/net/nf_conntrack ] || [ -e /proc/net/ip_conntrack ]; then
      echo fw_conntrack
      echo fw_forwarded_local
    fi
    if [ -x /bin/netstat ]; then
      echo netstat
    fi
  } | sort >expected_plugins
  test_cmp expected_plugins all_without_network_interfaces
'

test_expect_success "plugins are executed as 'nobody' by default" '
    cat >/etc/munin/plugins/test-id <<EOF
#!/bin/sh
printf "user.value "
# exit with success - otherwise munin-node hides potential error output
id --user --name 2>&1 || true
EOF
    chmod +x /etc/munin/plugins/test-id
    service munin-node restart
    # give munin-node time to get ready for answering requests
    sleep 5
    printf "%s\\n" "fetch test-id" quit | nc localhost munin | grep -v "^#" >real_id_output
    cat >expected_id_output <<EOF
user.value nobody
.
EOF
    test_cmp expected_id_output real_id_output
'

test_done
