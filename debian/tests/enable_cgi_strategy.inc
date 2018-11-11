# reconfigure munin-master for the CGI strategy
#
# Include this snippet in any test requiring the CGI strategy.


CONF_DIR="/etc/munin/munin-conf.d"
CONF_FILE_PATTERN="munin-cron-test-XXXXXX.conf"
CONF_FILE_GLOB="munin-cron-test-*.conf"


# delete potential stale configuration fragments
find "$CONF_DIR" -type f -name "$CONF_FILE_GLOB" -delete


configure_munin_for_strategy() {
    # create configuration file for cron strategy
    temp_conf_file=$(mktemp -p /etc/munin/munin-conf.d "$CONF_FILE_PATTERN")
    cat >"$temp_conf_file" <<EOF
graph_strategy cgi
html_strategy  cgi
EOF
    chmod 0644 "$temp_conf_file"
}


configure_apache2_for_strategy() {
    # do nothing if apache is not installed
    [ -x /usr/sbin/apache2 ] || return 0

    local apache2_conf="/etc/apache2/conf-enabled/munin.conf"

    sed -i 's/^#\(ScriptAlias \/munin \)/\1/' "$apache2_conf"
    sed -i 's/^Alias \/munin /#\0/' "$apache2_conf"
    a2enmod cgid
    service apache2 restart
}


configure_munin_for_strategy
configure_apache2_for_strategy


# set flag for the following tests
export MUNIN_TEST_CGI_ENABLED=1
