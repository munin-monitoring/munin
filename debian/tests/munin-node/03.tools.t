#!/bin/sh
#
# verify that other tools related to munin-node work
#

test_description="munin-node plugins"

. /usr/share/sharness/sharness.sh


# TODO: remove this test (and the error redirection in the following test) as soon as "munindoc"
#     does not write to stderr anymore
test_expect_failure "munin-doc may not emit error output" '
  /usr/bin/munindoc df >/dev/null 2>munindoc_stderr
  test_must_be_empty munindoc_stderr
'

# TODO: remove the stderr redirection as soon as the issue above is fixed
test_expect_success "munin-doc" '
  /usr/bin/munindoc df 2>/dev/null | grep -q "disk"
'

test_expect_success "munin-run" '
  /usr/sbin/munin-run memory | grep -q "^free"
'

test_expect_success "munin-node-configure" '
  munin-node-configure
'

test_done
