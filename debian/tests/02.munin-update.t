#!/bin/sh

test_description="munin-update"

. ./sharness.sh

test_expect_success "munin-update" "
  runuser munin /usr/share/munin/munin-update
"

test_expect_success "munin-limits" "
  runuser munin /usr/share/munin/munin-limits
"

test_done
