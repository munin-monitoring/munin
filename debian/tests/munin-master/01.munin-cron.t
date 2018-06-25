#!/bin/sh

test_description="munin run (cron strategy)"

. debian/tests/sharness.sh

setup() {
    temp_conf_file=$(mktemp /etc/munin/munin-conf.d/autopkgtest.XXXXXXXX.conf)
    chmod 0644 $temp_conf_file
    trap "rm $temp_conf_file" EXIT

    cat >> $temp_conf_file <<EOF
graph_strategy cron
html_strategy  cron
EOF
}

test_expect_success "setup" "
  setup
"

test_expect_success "munin-update" "
  setuidgid munin /usr/share/munin/munin-update
"

test_expect_success "munin-limits" "
  setuidgid munin /usr/share/munin/munin-limits
"

test_expect_success "munin-graph" "
  setuidgid munin /usr/share/munin/munin-graph
"

test_expect_success "munin-html" "
  setuidgid munin /usr/share/munin/munin-html
"

test_done
