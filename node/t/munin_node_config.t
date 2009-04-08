use warnings;
use strict;

use Test::More tests => 36;

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

    eval {
        $conf->_parse_line("foo");
    };
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
}


### Default group

{
    my $gid   = (split / /, $GID)[0];
    my $gname = getgrgid $gid;

    my @res = $conf->_parse_line("default_client_group $gname");
    is_deeply(\@res, [defgroup => $gid], 'Parsing default group');
    
    eval {
        $conf->_parse_line("default_client_group xxxyyyzzz");
    };
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
    is_deeply(\@res, [allow_deny => ['allow', '127\.0\.0\.1']], 'Parsing allow');  
}

{
    my @res = $conf->_parse_line('deny 127\.0\.0\.1');
    is_deeply(\@res, [allow_deny => ['deny', '127\.0\.0\.1']], 'Parsing deny');  
}


### tls

{
    my @res = $conf->_parse_line('tls paranoid');
    is_deeply(\@res, [tls => 'paranoid'], 'Parsing tls');  

}

###############################################################################
#                       _ S T R I P _ C O M M E N T

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
#                         R E I N I T I A L I Z E

{
    my $expected = {foo => 'bar'};
    $conf->reinitialize($expected);
    is_deeply($conf, $expected, "Reinitialize with new values");

    $conf->reinitialize();
    is_deeply($conf, {}, "Reinitialize to empty state");
}


###############################################################################
#                         P A R S E _ C O N F I G

{
    $conf->reinitialize();
    $conf->parse_config(*DATA);
    my $expected = {
        fqdn => 'foo.example.com',
        tls => 'enabled',
        allow_deny => [
            ['allow', '^127\\.0\\.0\\.\d+$'],
            ['allow', '^10\\.0\\.0\\.\d+$']
        ],
        sconf => {
            'setsid' => 'yes',
            'background' => '1',
            'log_file' => '/var/log/munin/munin-node.log',
            'host' => '*',
            'setseid' => '1',
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
#                  _ A D D _ A L L O W _ D E N Y _ R U L E

{
    $conf->reinitialize();

    $conf->_add_allow_deny_rule(['deny', 'foo']);
    is_deeply($conf, {allow_deny => [['deny', 'foo']]});

    eval {
        $conf->_add_allow_deny_rule(['allow', 'foo']);
    };
    like($EVAL_ERROR, qr/You can't mix allow and deny/);
}


{
    $conf->reinitialize();

    $conf->_add_allow_deny_rule(['allow', 'foo']);
    is_deeply($conf, {allow_deny => [['allow', 'foo']]});

    eval {
        $conf->_add_allow_deny_rule(['deny', 'foo']);
    };
    like($EVAL_ERROR, qr/You can't mix allow and deny/);
}



###############################################################################
#                    _ P A R S E _ P L U G I N _ L I N E


### user

{
    my $uname = getpwuid $UID;

    my @res = $conf->_parse_plugin_line("user $uname");
    is_deeply(\@res, [user => $UID], 'Parsing plugin user name');

    @res = $conf->_parse_plugin_line("user $UID");
    is_deeply(\@res, [user => $UID], 'Parsing plugin user ID');

}

### group

{
    my $gid   = (split / /, $GID)[0];
    my $gname = getgrgid $gid;

    my @res = $conf->_parse_plugin_line("group $gname");
    is_deeply(\@res, [group => $gid], 'Parsing plugin group');
}


{
    my $gids = $GID;
    $gids =~ tr/ /,/;

    my @res = $conf->_parse_plugin_line("group $gids");
    is_deeply(\@res, [group => $GID], 'Parsing plugin group (many)');

    my $gids_with_optional = "$gids,(999999999)";
    @res = $conf->_parse_plugin_line("group $gids_with_optional");
    is_deeply(\@res, [group => $GID], 'Parsing plugin group (many with optional nonexistent)');
}


{
    eval {
        $conf->_parse_plugin_line("group xxxyyyzzz");
    };
    like($@, qr{Group 'xxxyyyzzz' does not exist},
         "Nonexistent group throws exception");
}


### environment

{
    my @res = $conf->_parse_plugin_line("env.foo fnord");
    is_deeply(\@res, [ env => { foo => 'fnord' } ], 'Parsing environment variable');
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

    #print '-'x70, "\n", $stderr, '-'x70, "\n", $@, '-'x70, "\n";

    is($@, '', "No exceptions");
    like($stderr, qr{Clutter before section start}, "Clutter file is skipped");

    #use Data::Dumper; warn Dumper($conf);

    is_deeply($conf, {
        sconfdir => $sconfdir,
        sconf=>{
            Foo    => {user => 0, env => {baz => 'zing'}},
            'Foo*' => {group => 0, env => {bar => 'zap'}},
            'F*'   => {env => {bar => 'zoo'}},
        },
    }, "Checking sconf");

    $conf->apply_wildcards();
    is_deeply($conf, {
        sconfdir => $sconfdir,
        sconf=>{
            Foo => {
                user => 0, 
                group => 0, 
                env => {
                    baz => 'zing', 
                    bar => 'zap',
                }
            }
        }
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
setseid 1

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
