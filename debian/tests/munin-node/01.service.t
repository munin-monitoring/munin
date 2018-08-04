#!/bin/sh
#
# verify that munin-node can be started and stopped
#

test_description="munin-node service"

. /usr/share/sharness/sharness.sh


test_expect_success "status (should be started by default)" "
  service munin-node status
"

test_expect_success "restart" "
  service munin-node restart
"

test_expect_success "status (after restart)" "
  service munin-node status
"

test_expect_success "stop" "
  service munin-node stop
"

test_expect_success "status (after stop)" "
  test_expect_code 3 service munin-node status
"

test_expect_success "start" "
  service munin-node start
"

test_expect_success "status (after start)" "
  service munin-node status
"

check_port() {
    while ! nc -z localhost 4949; do
        a=$(expr $a + 1)
        if [ $a = 10 ]; then
            return 1
        fi
        sleep 1;
    done
}

test_expect_success "munin node port listening" "
  check_port
"

test_done
