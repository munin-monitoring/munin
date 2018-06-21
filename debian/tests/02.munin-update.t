#!/bin/sh

set -eu

test_description="munin-update"

. ./sharness.sh

test_expect_success "munin-update" "
  runuser -u munin /usr/bin/munin-update
"

test_expect_success "munin-limits" "
  runuser -u munin /usr/bin/munin-limits
"

test_done
