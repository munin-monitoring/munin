#!/bin/sh

set -eu

test_description="munin-node"

. ./sharness.sh

test_expect_success "munin-node-configure" "
  munin-node-configure
"

test_expect_success "munin-node running?" "
  pgrep -u root munin-node
"

test_expect_success "munin node listening?" "
  echo quit | nc localhost 4949
"

test_done
