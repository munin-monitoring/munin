#!/bin/sh

test_description="munin-master components"

. /usr/share/sharness/sharness.sh


test_expect_success "munin-update" '
  setuidgid munin /usr/bin/munin-update
'

# TODO: change into "test_expect_success" and remove redirection as soon as upstream fixed "munin-limits"
#       see https://github.com/munin-monitoring/munin/issues/1133
test_expect_failure "munin-limits" '
  setuidgid munin /usr/bin/munin-limits 2>/dev/null
'

test_expect_success "munin-cron" '
  setuidgid munin /usr/bin/munin-cron
'

test_done
