#!/bin/sh

# "sharness" (v1.0) currently fails with "-u"
set -e

test_description="munin-node"

. /usr/share/sharness/sharness.sh

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
