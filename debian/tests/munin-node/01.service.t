#!/bin/sh
#
# verify that munin-node can be started and stopped
#

test_description="munin-node service"

. /usr/share/sharness/sharness.sh


test_expect_success "status (should be started by default)" '
  service munin-node status
'

test_expect_success "restart" '
  service munin-node restart
'

test_expect_success "status (after restart)" '
  service munin-node status
'

test_expect_success "stop" '
  service munin-node stop
'

test_expect_success "status (after stop)" '
  test_expect_code 3 service munin-node status
'

test_expect_success "start" '
  service munin-node start
'

test_expect_success "status (after start)" '
  service munin-node status
'

test_expect_success "munin node port listening" '
  echo quit | nc localhost 4949
'

test_done
