#!/bin/sh

test_description="munin-update"

. ./sharness.sh

test_expect_success "munin-update" "
  setuidgid munin /usr/share/munin/munin-update
"

test_expect_success "munin-limits" "
  setuidgid munin /usr/share/munin/munin-limits
"

test_expect_success "munin-html" "
  setuidgid munin /usr/share/munin/munin-html
"

test_expect_success "munin-graph" "
  setuidgid munin /usr/share/munin/munin-graph --cron
"

test_done
