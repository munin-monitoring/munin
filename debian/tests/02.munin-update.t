#!/bin/sh

test_description="munin-update"

. ./sharness.sh

test_expect_success "munin-update" "
  setuidgid munin /usr/share/munin/munin-update
"

test_expect_success "munin-limits" "
  setuidgid munin /usr/share/munin/munin-limits
"

test_done
