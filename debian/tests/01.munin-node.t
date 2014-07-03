#!/bin/sh

test_description="munin-node"

. ./sharness.sh

test_expect_success "munin-node service status" "
  /usr/sbin/invoke-rc.d --force munin-node status
"

test_expect_success "munin-node listening" "
  sleep 5
  /usr/lib/nagios/plugins/check_tcp -H 127.0.0.1 -p 4949 -v -e munin
"

test_done
