# reconfigure munin-master for the CGI strategy
#
# Include this snippet in any test requiring the CGI strategy.


CONF_DIR="/etc/munin/munin-conf.d"
CONF_FILE_PATTERN="munin-cron-test-XXXXXX.conf"
CONF_FILE_GLOB="munin-cron-test-*.conf"


# delete potential stale configuration fragments
find "$CONF_DIR" -type f -name "$CONF_FILE_GLOB" -delete

# create configuration file for cron strategy
temp_conf_file=$(mktemp -p /etc/munin/munin-conf.d "$CONF_FILE_PATTERN")
trap 'rm "$temp_conf_file"' EXIT

cat >"$temp_conf_file" <<EOF
graph_strategy cgi
html_strategy  cgi
EOF

chmod 0644 "$temp_conf_file"

# set flag for the following tests
export MUNIN_TEST_CGI_ENABLED=1
