#!/bin/sh
#
# verify that other tools related to munin-node work
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


test_expect_success "munin-doc" '
  /usr/bin/munin-doc df | grep -q "disk"
'

test_expect_success "munin-run" '
  /usr/bin/munin-run memory | grep -q "^free"
'

test_expect_success "munin-node-configure" '
  munin-node-configure
'

test_done
