# vim: ts=4 : et

use warnings;
use strict;

use Test::More tests => 43;

use FindBin;
use English qw(-no_match_vars);
use Munin::Common::Defaults;

use_ok('Munin::Node::Config');

my $conf = Munin::Node::Config->instance();
isa_ok($conf, 'Munin::Node::Config');


###############################################################################
#                       _ P A R S E _ L I N E

### Corner cases
{
    is($conf->_parse_line(""), undef, "Empty line is undef");

    eval { $conf->_parse_line("foo") };
    like($@, qr{Line is not well formed}, "Need a name and a value");

    is($conf->_parse_line("#foo"), undef, "Comment is undef");
}


### Hostname
{
    my @res = $conf->_parse_line("hostname foo");
    is_deeply(\@res, [fqdn => 'foo'], 'Parsing host name');

    # The parser is quite forgiving ...
    @res = $conf->_parse_line("hostname foo bar");
    is_deeply(\@res, [fqdn => 'foo bar'],
              'Parsing invalid host name gives no error');
}


### Default user
{
    my $uname = getpwuid $UID;

    my @res = $conf->_parse_line("default_client_user $uname");
    is_deeply(\@res, [defuser => $UID], 'Parsing default user name');

    @res = $conf->_parse_line("default_client_user $UID");
    is_deeply(\@res, [defuser => $UID], 'Parsing default user ID');
    
    eval { $conf->_parse_line("default_client_user xxxyyyzzz") };
    like($@, qr{Default user does not exist}, "Default user exists");
}


### Default group
{
    my $gid   = (split / /, $GID)[0];
    my $gname = getgrgid $gid;

    my @res = $conf->_parse_line("default_client_group $gname");
    is_deeply(\@res, [defgroup => $gid], 'Parsing default group');

    eval { $conf->_parse_line("default_client_group xxxyyyzzz") };
    like($@, qr{Default group does not exist}, "Default group exists");
}


### Paranoia
{
    my @res = $conf->_parse_line("paranoia off");
    is_deeply(\@res, [paranoia => 0], 'Parsing paranoia');
}


### allow_deny
{
    my @res = $conf->_parse_line('allow 127\.0\.0\.1');
    is_deeply(\@res, [], 'Parsing: allow is ignored');
}

{
    my @res = $conf->_parse_line('deny 127\.0\.0\.1');
    is_deeply(\@res, [], 'Parsing: deny is ignored');
}


### tls
{
    my @res = $conf->_parse_line('tls paranoid');
    is_deeply(\@res, [tls => 'paranoid'], 'Parsing tls');

}

###############################################################################
#  _strip_comment
{
    my $str = "#Foo" ;
    $conf->_strip_comment($str);
    is($str, "", "Strip comment");
}

{
    my $str = "foo #Foo" ;
    $conf->_strip_comment($str);
    is($str, "foo ", "Strip comment 2");
}

{
    my $str = "foo" ;
    $conf->_strip_comment($str);
    is($str, "foo", "Strip comment 3");
}


###############################################################################
#  reinitialize
{
    my $expected = {foo => 'bar'};
    $conf->reinitialize($expected);
    is_deeply($conf, $expected, "Reinitialize with new values");

    my $oldconf = $conf;

    $conf->reinitialize();
    is_deeply($conf, {}, "Reinitialize to empty state");

    is($conf, $oldconf, "Reinitialize preserves config references");
}


###############################################################################
#  parse_config
{
    $conf->reinitialize();
    $conf->parse_config(*DATA);
    my $expected = {
        fqdn => 'foo.example.com',
        tls => 'enabled',
        sconf => {
            'setsid' => 'yes',
            'background' => '1',
            'log_file' => '/var/log/munin/munin-node.log',
            'host' => '*',
            'setsid' => '1',
            'pid_file' => '/var/run/munin/munin-node.pid',
            'group' => 'root',
            'log_level' => '4',
            'user' => 'root',
        },
        ignores => [
            '~$',
            '\\.bak$',
            '%$',
            '\\.dpkg-(tmp|new|old|dist)$',
            '\\.rpm(save|new)$',
            '\\.pod$',
        ],
    };
    is_deeply($conf, $expected, "Parsing a test config");
}


###############################################################################
# _parse_plugin_line

### malformed line
{
    eval { $conf->_parse_plugin_line("") };
    like($@, qr{Line is not well formed}, "Empty line is an error");
}
{
    eval { $conf->_parse_plugin_line("blah") };
    like($@, qr{Line is not well formed}, "line without a value is an error");
}
{
    eval { $conf->_parse_plugin_line("blah blah blah") };
    like($@, qr{Failed to parse line}, "Unknown variable name is an error");
}


### user
{
    my $uname = getpwuid $UID;

    my @res = $conf->_parse_plugin_line("user $uname");
    is_deeply(\@res, [user => $uname], 'Parsing plugin user name');

    @res = $conf->_parse_plugin_line("user $UID");
    is_deeply(\@res, [user => $UID], 'Parsing plugin user ID');
}

### group
my @gids = split / /, $GID;
my $gid  = $gids[0];

(my $gid_list = $GID) =~ tr/ /,/;
my $gname = getgrgid $gid;

{
    my @res = $conf->_parse_plugin_line("group $gname");
    is_deeply(\@res, [group => [ $gname ] ], 'Parsing plugin group');
}
{
    my @res = $conf->_parse_plugin_line("group $gid_list");
    is_deeply(\@res, [group => [ @gids ] ], 'Parsing plugin group (many)');
}
{
    my @res = $conf->_parse_plugin_line("group $gid_list, (999999999)");
    is_deeply(\@res, [group => [ @gids, '(999999999)' ] ],
        'Parsing plugin group (many with optional nonexistent)');
}
{
    my @res = $conf->_parse_plugin_line("group xxxyyyzzz");
    is_deeply(\@res, [group => [ 'xxxyyyzzz' ]], 'Parsing unknown group');
}

### command
{
    my @res = $conf->_parse_plugin_line('command shutdown -h now');
    is_deeply(\@res, [command => [ 'shutdown', '-h', 'now' ] ], 'command line');
}
{
    my @res = $conf->_parse_plugin_line('command sudo -u root %c');
    is_deeply(\@res, [command => [ 'sudo', '-u', 'root', '%c' ] ],
        'command line with %c expansion'
    );
}

### host_name
{
    my @res = $conf->_parse_plugin_line('host_name server.example.com');
    is_deeply(\@res, [host_name => 'server.example.com'], 'parsing host_name');
}

### timeout
{
    my @res = $conf->_parse_plugin_line('timeout 20');
    is_deeply(\@res, [timeout => 20], 'parsing timeout');
}
{
    my @res = $conf->_parse_plugin_line('timeout aeons');
    is_deeply(\@res, [timeout => 'aeons'], 'non-numeric timeout is valid');
}


### environment
{
    my @res = $conf->_parse_plugin_line("env.foo fnord");
    is_deeply(\@res, [ env => { foo => 'fnord' } ], 'Parsing environment variable');
}
{
    eval { $conf->_parse_plugin_line("env foo = fnord") };
    like($@, qr{Deprecated.*'env\.foo fnord'},
         "Old way of configuring plugin environment variables throws exception");
}


###############################################################################
#     P R O C E S S _ P L U G I N _ C O N F I G U R A T I O N _ F I L E S

{
    # Capture STDERR in a string
    my $stderr;
    open my $olderr, '>&', *STDERR;
    close STDERR;
    open STDERR, '>', \$stderr or die $!;

    my $sconfdir = "$FindBin::Bin/config/plugin-conf.d";

    eval {
        $conf->reinitialize({
            sconfdir => $sconfdir,
        });
        $conf->process_plugin_configuration_files();
    };

    # Close and restore STDERR to original condition.
    close STDERR;
    open STDERR, '>&', $olderr;

    is($@, '', "No exceptions");
    like($stderr, qr{Clutter before section start}, "Clutter file is skipped");

    is_deeply($conf, {
        sconfdir => $sconfdir,
        sconf=>{
            Foo    => {user => 'root', env => {baz => 'zing'}, update_rate => 86400 },
            'Foo*' => {group => [ 'root' ], env => {bar => 'zap'}},
            'F*'   => {env => {bar => 'zoo'}},
        },
    }, "Checking sconf");

    $conf->apply_wildcards(qw| Foo Fnord boF |);
    is_deeply($conf, {
        sconfdir => $sconfdir,
        sconf=>{
            Foo => {
                user => 'root',
                group => [ 'root' ],
                env => {
                    baz => 'zing',
                    bar => 'zap',
                },
                update_rate => 86400,
            },
            Fnord => {
                env => {
                    bar => 'zoo',
                },
            },
        },
    }, "Checking sconf wildcards");
}

__DATA__
#
# Example config-file for munin-node
#

log_level 4
log_file /var/log/munin/munin-node.log
pid_file /var/run/munin/munin-node.pid

background 1
setsid 1

user root
group root
setsid yes

# Regexps for files to ignore

ignore_file ~$
ignore_file \.bak$
ignore_file %$
ignore_file \.dpkg-(tmp|new|old|dist)$
ignore_file \.rpm(save|new)$
ignore_file \.pod$

# Set this if the client doesn't report the correct hostname when
# telnetting to localhost, port 4948
#
host_name foo.example.com

# A list of addresses that are allowed to connect.  This must be a
# regular expression, due to brain damage in Net::Server, which
# doesn't understand CIDR-style network notation.  You may repeat
# the allow line as many times as you'd like

allow ^127\.0\.0\.\d+$
allow ^10\.0\.0\.\d+$

# Which address to bind to;
host *
# host 127.0.0.1

tls enabled
