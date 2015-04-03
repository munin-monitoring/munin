#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;
my $build = Module::Build->current;
my $log_file = $build->install_path('MUNIN_LOGDIR') . '/munin-node.log';
my $pid_file = $build->install_path('MUNIN_RUNDIR') . '/munin-node.pid';

my $output_file = shift;
open my $fh, ">", $output_file or die "Can't open $output_file: $!";


print $fh <<'EOF';
#
# Example config-file for munin-node
#

log_level 4
EOF

print $fh <<"EOF";
log_file $log_file
pid_file $pid_file
EOF

print $fh <<'EOF';

background 1
setsid 1

user root
group root

# This is the timeout for the whole transaction.
# Units are in sec. Default is 15 min
#
# global_timeout 900

# This is the timeout for each plugin.
# Units are in sec. Default is 1 min
#
# timeout 60

# Regexps for files to ignore
ignore_file [\#~]$
ignore_file DEADJOE$
ignore_file \.bak$
ignore_file %$
ignore_file \.dpkg-(tmp|new|old|dist)$
ignore_file \.rpm(save|new)$
ignore_file \.pod$

# Set this if the client doesn't report the correct hostname when
# telnetting to localhost, port 4949
#
#host_name myhostname.example.com

# A list of addresses that are allowed to connect.  This must be a
# regular expression, since Net::Server does not understand CIDR-style
# network notation unless the perl module Net::CIDR is installed.  You
# may repeat the allow line as many times as you'd like

allow ^127\.0\.0\.1$
allow ^::1$

# If you have installed the Net::CIDR perl module, you can use one or more
# cidr_allow and cidr_deny address/mask patterns.  A connecting client must
# match any cidr_allow, and not match any cidr_deny.  Note that a netmask
# *must* be provided, even if it's /32
#
# Example:
#
# cidr_allow 127.0.0.1/32
# cidr_allow 192.0.2.0/24
# cidr_deny  192.0.2.42/32

# Which address to bind to;
host *
# host 127.0.0.1

# And which port
port 4949

EOF
