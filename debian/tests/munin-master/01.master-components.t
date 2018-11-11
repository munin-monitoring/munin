#!/bin/sh

test_description="munin-master components"

. /usr/share/sharness/sharness.sh


test_expect_success "munin-update" '
  setuidgid munin /usr/bin/munin-update
'

test_expect_success "munin-limits" '
  setuidgid munin /usr/bin/munin-limits
'

test_expect_success "munin-cron" '
  setuidgid munin /usr/bin/munin-cron
'

test_done
