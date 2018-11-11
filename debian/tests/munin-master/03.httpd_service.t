#!/bin/sh
#
# verify that munin-httpd can be started and stopped
#

test_description="munin-httpd service"

. /usr/share/sharness/sharness.sh


test_expect_success "status (should be started by default)" '
  service munin-httpd status
'

test_expect_success "restart" '
  service munin-httpd restart
'

test_expect_success "status (after restart)" '
  service munin-httpd status
'

test_expect_success "stop" '
  service munin-httpd stop
'

test_expect_success "status (after stop)" '
  test_expect_code 3 service munin-httpd status
'

test_expect_success "start" '
  service munin-httpd start
'

test_expect_success "status (after start)" '
  service munin-httpd status
'

# munin-httpd is not ready immeadiately after startup - thus we need to wait a bit.
# But since even "nc -w 10 ..." returns immediately, if the port is still closed. Thus we use the
# manual approach of waiting for the service to be ready.
check_port() {
  local port="$1"
  local count=0
  while [ "$count" -lt 10 ]; do
    nc -z localhost "$port" && return
    sleep 1
  done
  return 1
}

test_expect_success "munin-httpd port listening" '
  check_port 4948
'

test_done
