#!/bin/sh

test_description="munin-node"

. ./sharness.sh

test_expect_success "munin-node-configure" "
  munin-node-configure
"

test_expect_success "munin-node running?" <<EOF
pgrep -u root munin-node
EOF

test_expect_success "munin node listening?" <<EOF
echo quit | nc localhost 4949
EOF

test_done
