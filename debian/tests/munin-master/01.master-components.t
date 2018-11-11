#!/bin/sh

test_description="munin-master components"

. /usr/share/sharness/sharness.sh


# the variable may be set by wrapper scripts
MUNIN_TEST_CGI_ENABLED=${MUNIN_TEST_CGI_ENABLED:-0}


test_expect_success "munin-update" '
  setuidgid munin /usr/share/munin/munin-update
'

test_expect_success "munin-limits" '
  setuidgid munin /usr/share/munin/munin-limits
'

test_expect_success "munin-html: no files in /var/cache/munin/www/ before first run" '
  find /var/cache/munin/www/ -mindepth 1 >unwanted_existing_files
  test_must_be_empty unwanted_existing_files
'

test_expect_success "munin-html: running" '
  setuidgid munin /usr/share/munin/munin-html
'

test_expect_success "munin-html: generated files in /var/cache/munin/www/static/" '
  [ -n "$(find /var/cache/munin/www/static/ -mindepth 1)" ]
'

if [ "$MUNIN_TEST_CGI_ENABLED" = "1" ]; then
  test_expect_success "CGI strategy: do not generate static HTML files" '
    find /var/cache/munin/www/ -mindepth 1 | grep -vE "/static(/|$)" >unwanted_existing_files
    test_must_be_empty unwanted_existing_files
  '
else
  test_expect_success "cron strategy: generate static HTML files" '
    [ -s /var/cache/munin/www/index.html ]
  '
fi

test_expect_success "munin-graph" '
  setuidgid munin /usr/share/munin/munin-graph --cron
'

if [ "$MUNIN_TEST_CGI_ENABLED" = "1" ]; then
  test_expect_success "CGI strategy: do not generate static graph files" '
    find /var/cache/munin/www/ -type f -name "*.png" | grep -v "/static/" >unwanted_existing_files
    test_must_be_empty unwanted_existing_files
  '
else
  test_expect_success "cron strategy: generate static graph files" '
    [ -s /var/cache/munin/www/localdomain/localhost.localdomain/df-day.png ]
  '
fi

test_expect_success "munin-cron" '
  setuidgid munin /usr/bin/munin-cron
'

test_done
