#!/bin/sh

# "sharness" (v1.0) currently fails with "-u"
set -e

test_description="munin-update"

. /usr/share/sharness/sharness.sh

test_expect_success "munin-update" "
  runuser -u munin /usr/bin/munin-update
"

test_expect_success "munin-limits" "
  runuser -u munin /usr/bin/munin-limits
"

test_done
