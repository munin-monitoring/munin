use strict;
use warnings;

use Test::More tests => 264;

use Munin::Node::Configure::Plugin;

use constant FOUND_DIRECTORY_SCRATCH => eval { require Directory::Scratch };


# helper function.  returns a Plugin object
sub gen_plugin
{
    my $name = shift;
    return Munin::Node::Configure::Plugin->new(
        name => $name,
        path => "/usr/share/munin/plugins/$name"
    );
}


### START TESTS ###############################################################################

### new
{
    my $plugin = new_ok('Munin::Node::Configure::Plugin' => [
        path => '/usr/share/munin/plugins/memory',
        name => 'memory'
    ], 'Simple plugin');
}
{
    my $wcplugin = new_ok('Munin::Node::Configure::Plugin' => [
        path => '/usr/share/munin/plugins/if_',
        name => 'if_'
    ], 'Wildcard plugin');
}


### is_wildcard
{
    my $p = gen_plugin('memory');
    ok(! $p->is_wildcard, 'Non-wildcard plugin is identfied as such');
}
{
    my $wcp = gen_plugin('if_');
    ok($wcp->is_wildcard, 'Wildcard plugin is identfied as such');
}


### is_snmp
{
    my $p = gen_plugin('memory');
    ok(! $p->is_snmp, 'Non-wildcard plugin is not SNMP');
}
{
    my $p = gen_plugin('if_');
    ok(! $p->is_snmp, 'Wildcard plugin is not SNMP');
}
{
    my $p = gen_plugin('snmp__memory');
    ok($p->is_snmp, 'SNMP plugin is SNMP');
}
{
    my $p = gen_plugin('snmp__if_err_');
    ok($p->is_snmp, 'Wildcard SNMP plugin is SNMP');
}


### in_family
{
    my $p = gen_plugin('memory');
    $p->{family} = 'auto';

    ok( $p->in_family(qw( auto manual contrib ), 'is in list of families'));
    ok(!$p->in_family(qw( snmpauto            ), 'is not in other list of families'));
}


### is_installed
{
    my $p = gen_plugin('memory');

    is($p->is_installed,   'no', 'Not installed by default');

    $p->add_instance('memory');
    is($p->is_installed, 'yes', 'Installed after instance is added');
}
{
    my $p = gen_plugin('if_');

    is($p->is_installed,   'no', 'Not installed by default (wildcard)');

    $p->add_instance('if_eth0');
    is($p->is_installed, 'yes', 'Installed after instance is added (wc)');
}
{
    my $p = gen_plugin('snmp__memory');

    is($p->is_installed,   'no', 'Not installed by default (snmp)');

    $p->add_instance('snmp_switch.example.com_memory');
    is($p->is_installed, 'yes', 'Installed after instance is added (snmp)');
}
{
    my $p = gen_plugin('snmp__memory');

    is($p->is_installed,   'no', 'Not installed by default (snmp v3)');

    $p->add_instance('snmpv3_switch.example.com_memory');
    is($p->is_installed, 'yes', 'Installed after instance is added (snmp v3)');
}
{
    my $p = gen_plugin('snmp__if_');

    is($p->is_installed,   'no', 'Not installed by default (wc snmp)');

    $p->add_instance('snmp_switch.example.com_if_2');
    is($p->is_installed, 'yes', 'Installed after instance is added (wc snmp)');
}
{
    my $p = gen_plugin('snmp__if_');

    is($p->is_installed,   'no', 'Not installed by default (wc snmp v3)');

    $p->add_instance('snmpv3_switch.example.com_if_1');
    is($p->is_installed, 'yes', 'Installed after instance is added (wc snmp v3)');
}


### _reduce_wildcard
### _expand_wildcard
{
    my $p = gen_plugin('memory');

    is($p->_reduce_wildcard('memory'), (), 'Simple plugin - reduce');
    # FIXME: what is the sane behaviour?  can this ever happen normally?
    #is($p->_expand_wildcard(''), '', 'Simple plugin');
}
{
    my $p = gen_plugin('if_');
    is($p->_reduce_wildcard('if_eth0'), 'eth0', 'Wildcard plugin - reduce');
    is($p->_expand_wildcard('eth0'), 'if_eth0', 'Wildcard plugin - expand');
}
{
    my $p = gen_plugin('snmp__load');
    is(
        $p->_reduce_wildcard('snmp_switch.example.com_load'),
        'switch.example.com',
        'SNMP plugin - reduce'
    );
    is(
        $p->_reduce_wildcard('snmpv3_switch.example.com_load'),
        'switch.example.com',
        'Version 3 SNMP plugin - reduce'
    );

    is(
        $p->_expand_wildcard([ 'switch.example.com' ]),
        'snmp_switch.example.com_load',
        'SNMP plugin - expand'
    );
}
{
    my $p = gen_plugin('snmp__if_');
    is(
        $p->_reduce_wildcard('snmp_switch.example.com_if_1'),
        'switch.example.com/1',
        'SNMP plugin with wildcard - reduce'
    );
    is(
        $p->_reduce_wildcard('snmpv3_switch.example.com_if_1'),
        'switch.example.com/1',
        'Version 3 SNMP plugin with wildcard - reduce'
    );
    is(
        $p->_expand_wildcard([ 'switch.example.com', 1 ]),
        'snmp_switch.example.com_if_1',
        'SNMP plugin with wildcard - expand'
    );
}


### _remove
### _add
### _same
{
    my @tests = (
        [
            [ [qw/a b c/], [qw/a b c/] ],
            [ [qw/a b c/], [], [] ],
            'All the suggestions are already installed',
        ],
        [
            [ [], [qw/a b c/] ],
            [ [], [qw/a b c/], [] ],
            'None of the suggestions are currently installed',
        ],
        [
            [ [qw/a b c/], [] ],
            [ [], [], [qw/a b c/] ],
            'No suggestions offered (remove all)',
        ],
        [
            [ [qw/a b/], [qw/a b c/] ],
            [ [qw/a b/], [qw/c/], [] ],
            'Some plugin identities to be added',
        ],
        [
            [ [qw/a b c/], [qw/a b/] ],
            [ [qw/a b/], [], [qw/c/] ],
            'Some plugin identities to be removed',
        ],
        [
            [ [qw/a b c d e/], [qw/c d e f g/]  ],
            [ [qw/c d e/], [qw/f g/], [qw/a b/] ],
            'Some to be added, some removed, some common',
        ],
    );

    my $same   = \&Munin::Node::Configure::Plugin::_same;
    my $add    = \&Munin::Node::Configure::Plugin::_add;
    my $remove = \&Munin::Node::Configure::Plugin::_remove;

    foreach (@tests) {
        my ($in, $expected, $msg) = @$_;

        is_deeply([   $same->(@$in) ], $expected->[0], "$msg - same");
        is_deeply([    $add->(@$in) ], $expected->[1], "$msg - add");
        is_deeply([ $remove->(@$in) ], $expected->[2], "$msg - remove");
    }
}


### suggestion_string
{
    my $p = gen_plugin('memory');

    $p->parse_autoconf_response('no');
    is(
        $p->suggestion_string,
        'no',
        'Suggestion string - no'
    );
}
{
    my $p = gen_plugin('memory');

    $p->parse_autoconf_response('no (not a good idea)');
    is(
        $p->suggestion_string,
        'no [not a good idea]',
        'Suggestion string - no with reason'
    );
}
{
    my $p = gen_plugin('memory');

    $p->parse_autoconf_response('yes');
    is(
        $p->suggestion_string,
        'yes',
        'Suggestion string - yes'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('no');
    is(
        $p->suggestion_string,
        'no',
        'Suggestion string - no'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('no (not a good idea)');
    is(
        $p->suggestion_string,
        'no [not a good idea]',
        'Suggestion string - no with reason'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('no (not a good idea)');
    is(
        $p->suggestion_string,
        'no [not a good idea]',
        'Suggestion string - no with reason'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    is(
        $p->suggestion_string,
        'yes',                                  # FIXME: should this ever happen with a wc plugin?
        'Suggestion string - yes'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->parse_suggest_response(qw/alpha bravo charlie/);
    is(
        $p->suggestion_string,
        'yes (+alpha +bravo +charlie)',
        'Suggestion string - yes with plugins to add'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->parse_suggest_response(qw/alpha bravo charlie/);
    $p->add_instance('alpha');
    is(
        $p->suggestion_string,
        'yes (alpha +bravo +charlie)',
        'Suggestion string - yes with plugins to add and unchanged'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->parse_suggest_response(qw/alpha bravo charlie/);
    $p->add_instance('alpha');
    $p->add_instance('delta');
    is(
        $p->suggestion_string,
        'yes (alpha +bravo +charlie -delta)',
        'Suggestion string - yes with plugins to remove and unchanged'
    );
}
{
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->parse_suggest_response(qw/alpha bravo charlie/);
    $p->add_instance('alpha');
    $p->add_instance('delta');
    is(
        $p->suggestion_string,
        'yes (alpha +bravo +charlie -delta)',
        'Suggestion string - yes with plugins to add, remove and unchanged'
    );
}


### installed_services_string
{
    my $p = gen_plugin('memory');

    is($p->installed_services_string, '', 'No services installed');

    $p->add_instance('memory');
    is($p->installed_services_string, '', 'One service installed');
}
{
    my $p = gen_plugin('if_');

    is($p->installed_services_string, '', 'No wildcard services installed');

    $p->add_instance('if_eth0');
    is($p->installed_services_string, 'eth0', 'One wildcard service installed');

    $p->add_instance('if_eth1');
    is($p->installed_services_string, 'eth0 eth1', 'Several wildcard services installed');
}
{
    my $p = gen_plugin('snmp__load');

    is($p->installed_services_string, '', 'No SNMP services installed');

    $p->add_instance('snmp_switch.example.com_load');
    is($p->installed_services_string, 'switch.example.com', 'One SNMP host installed');

    $p->add_instance('snmp_10.0.0.12_load');
    is($p->installed_services_string, 'switch.example.com 10.0.0.12', 'Several SNMP hosts installed');

    $p->add_instance('snmpv3_server.example.com_load');
    is($p->installed_services_string, 'switch.example.com 10.0.0.12 server.example.com', 'One SNMP host installed');

    $p->add_instance('snmpv3_10.0.0.14_load');
    is($p->installed_services_string, 'switch.example.com 10.0.0.12 server.example.com 10.0.0.14', 'Several wildcard service installed');
}
{
    my $p = gen_plugin('snmp__if_');

    is($p->installed_services_string, '', 'No wildcard SNMP services installed');

    $p->add_instance('snmp_switch.example.com_if_1');
    is(
        $p->installed_services_string,
        'switch.example.com/1',
        'One SNMP host installed'
    );

    $p->add_instance('snmp_switch.example.com_if_2');
    is(
        $p->installed_services_string,
        'switch.example.com/1 switch.example.com/2',
        'Added another instance on the same host'
    );

    $p->add_instance('snmp_10.0.0.12_if_1');
    is(
        $p->installed_services_string,
        'switch.example.com/1 switch.example.com/2 10.0.0.12/1',
        'Added another instance on a second host'
    );

    $p->add_instance('snmpv3_server.example.com_if_123');
    is(
        $p->installed_services_string,
        'switch.example.com/1 switch.example.com/2 10.0.0.12/1 server.example.com/123',
        'Added an instance on a v3 host'
    );

    $p->add_instance('snmpv3_10.0.0.14_if_45');
    is(
        $p->installed_services_string,
        'switch.example.com/1 switch.example.com/2 10.0.0.12/1 server.example.com/123 10.0.0.14/45',
        'Added an instance on a v3 host'
    );
}


### _installed_links
### _suggested_links
### _installed_wild
### _suggested_wild
{
    my $p = gen_plugin('memory');

    is_deeply($p->_installed_links, [], 'no links by default');
    is_deeply($p->_installed_wild , [], 'no wildcards by default');
    is_deeply($p->_suggested_links, [], 'no suggestions by default');
    is_deeply($p->_suggested_wild , [], 'no suggested wildcards by default');

    $p->{default} = 'yes';  # it's ok to run it now
    $p->add_instance('memory');
    is_deeply($p->_installed_links, ['memory'], 'one link installed');
    is_deeply($p->_installed_wild , [],         'no wildcards reported');
}
{
    my $p = gen_plugin('if_');

    is_deeply($p->_installed_links, [], 'no links by default');
    is_deeply($p->_installed_wild , [], 'no wildcards by default');
    is_deeply($p->_suggested_links, [], 'no suggestions by default');
    is_deeply($p->_suggested_wild , [], 'no suggested wildcards by default');

    $p->{default} = 'yes';  # it's ok to run it now

    $p->add_instance('if_eth0');
    is_deeply($p->_installed_links, ['if_eth0'], 'one link installed');
    is_deeply($p->_installed_wild , ['eth0'],    'one wildcard');

    $p->add_instance('if_eth1');
    is_deeply($p->_installed_links, [qw/if_eth0 if_eth1/], 'two links installed');
    is_deeply($p->_installed_wild , [qw/eth0 eth1/],       'two wildcards');

    $p->parse_suggest_response('eth2');
    is_deeply($p->_suggested_links, [ 'if_eth2' ], 'with a suggestion');
    is_deeply($p->_suggested_wild , [ 'eth2' ],    'with a suggested wildcard');
}
{
    my $p = gen_plugin('snmp__load');

    $p->{default} = 'yes';  # it's ok to run it now

    $p->add_instance('snmp_switch.example.com_load');
    is_deeply($p->_installed_links, ['snmp_switch.example.com_load'], 'one link installed');
    is_deeply($p->_installed_wild , ['switch.example.com'],           'one wildcard');

    $p->add_instance('snmp_switch2.example.com_load');
    is_deeply($p->_installed_links,
                [qw/snmp_switch.example.com_load snmp_switch2.example.com_load/],
                'two links installed');
    is_deeply($p->_installed_wild , [qw/switch.example.com switch2.example.com/], 'two wildcards');

    $p->add_suggestions([ 'switch.example.com' ]);
    is_deeply($p->_suggested_links, [ 'snmp_switch.example.com_load' ], 'with a suggestion');
    is_deeply($p->_suggested_wild , [ 'switch.example.com' ],    'with a suggested wildcard');
}
{
    my $p = gen_plugin('snmp__if_');

    $p->{default} = 'yes';  # it's ok to run it now

    $p->add_instance('snmp_switch.example.com_if_1');
    is_deeply($p->_installed_links, ['snmp_switch.example.com_if_1'], 'one link installed');
    is_deeply($p->_installed_wild , ['switch.example.com/1'],         'one wildcard');

    $p->add_instance('snmp_switch.example.com_if_2');
    is_deeply($p->_installed_links,
                [qw/snmp_switch.example.com_if_1 snmp_switch.example.com_if_2/],
                'two links installed');
    is_deeply($p->_installed_wild , [qw{switch.example.com/1 switch.example.com/2}], 'two wildcards');

    $p->add_suggestions([ 'switch.example.com', '1' ]);
    is_deeply($p->_suggested_links, [ 'snmp_switch.example.com_if_1' ], 'with a suggestion');
    is_deeply($p->_suggested_wild , [ 'switch.example.com/1' ],    'with a suggested wildcard');
    undef $p;
}


### services_to_add, services_to_remove

## Simple plugin
{
    # not installed and shouldn't be
    my $p = gen_plugin('memory');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # not installed and should be
    my $p = gen_plugin('memory');
    $p->parse_autoconf_response('yes');

    is_deeply([ $p->services_to_add    ], ['memory'], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # installed and should be
    my $p = gen_plugin('memory');
    $p->parse_autoconf_response('yes');
    $p->add_instance('memory');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # installed and shouldn't be
    my $p = gen_plugin('memory');
    $p->parse_autoconf_response('no');
    $p->add_instance('memory');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], ['memory']);
}

## Wildcard plugin
{
    # not installed and shouldn't be
    my $p = gen_plugin('if_');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # not installed and should be
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->add_suggestions('eth0');

    is_deeply([ $p->services_to_add    ], ['if_eth0'], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # installed and should be
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('yes');

    $p->add_instance('if_eth0');
    $p->add_suggestions('eth0');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # installed and shouldn't be
    my $p = gen_plugin('if_');

    $p->parse_autoconf_response('no');

    $p->add_instance('if_eth0');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], ['if_eth0']);
}

## SNMP plugin
{
    # not installed and shouldn't be
    my $p = gen_plugin('snmp__memory');

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # not installed and should be
    my $p = gen_plugin('snmp__memory');

    $p->parse_autoconf_response('yes');

    $p->add_suggestions([ 'switch.example.com' ]);
    $p->add_suggestions([ '10.0.0.19' ]);

    is_deeply(
        [ $p->services_to_add ],
        [ sort 'snmp_switch.example.com_memory', 'snmp_10.0.0.19_memory'], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
{
    # installed and should be
    my $p = gen_plugin('snmp__memory');

    $p->parse_autoconf_response('yes');

    $p->add_instance('snmp_switch.example.com_memory');
    $p->add_instance('snmp_10.0.0.19_memory');

    $p->add_suggestions([ 'switch.example.com' ]);
    $p->add_suggestions([ '10.0.0.19' ]);

    is_deeply([ $p->services_to_add    ], [], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
#{
#    # v3 installed and should be
#    my $p = gen_plugin('snmp__memory');
#
#    $p->parse_autoconf_response('yes');
#
#    $p->add_instance('snmpv3_switch.example.com_memory');
#    $p->add_instance('snmpv3_10.0.0.19_memory');
#
#    $p->add_suggestions([ 'switch.example.com' ]);
#    $p->add_suggestions([ '10.0.0.19' ]);
#
#    is_deeply([ $p->services_to_add    ], []);
#    is_deeply([ $p->services_to_remove ], []);
#}
{
    # some installed and should be
    my $p = gen_plugin('snmp__memory');

    $p->parse_autoconf_response('yes');

    $p->add_instance('snmp_switch.example.com_memory');

    $p->add_suggestions([ 'switch.example.com' ]);
    $p->add_suggestions([ '10.0.0.19' ]);

    is_deeply([ $p->services_to_add    ], [ 'snmp_10.0.0.19_memory' ], 'Add');
    is_deeply([ $p->services_to_remove ], []);
}
#{
#    # v3 some installed and should be
#    my $p = gen_plugin('snmp__memory');
#
#    $p->parse_autoconf_response('yes');
#
#    $p->add_instance('snmpv3_switch.example.com_memory');
#
#    $p->add_suggestions([ 'switch.example.com' ]);
#    $p->add_suggestions([ '10.0.0.19' ]);
#
#    is_deeply([ $p->services_to_add    ], [ 'snmp_10.0.0.19_memory' ], 'Add');
#    is_deeply([ $p->services_to_remove ], []);
#}
{
    # installed and shouldn't be
    my $p = gen_plugin('snmp__memory');

    $p->parse_autoconf_response('no');

    $p->add_instance('snmp_switch.example.com_memory');

    is_deeply([ $p->services_to_add    ], []);
    is_deeply([ $p->services_to_remove ], ['snmp_switch.example.com_memory']);
}
{
    # v3 installed and shouldn't be
    my $p = gen_plugin('snmp__memory');

    $p->parse_autoconf_response('no');

    $p->add_instance('snmpv3_switch.example.com_memory');

    is_deeply([ $p->services_to_add    ], []);
    is_deeply([ $p->services_to_remove ], ['snmpv3_switch.example.com_memory']);
}


## TODO: snmp wildcard




### read_magic_markers
SKIP: {
    skip 'Directory::Scratch not installed', 2
        unless FOUND_DIRECTORY_SCRATCH;

    my $file = Directory::Scratch->new->touch('foo/bar/baz', <<'EOF');
# Munin test plugin.   Does nothing, just contains magic markers
#
# #%# family=magic
# #%# capabilities=autoconf suggest other
EOF
    my $p = Munin::Node::Configure::Plugin->new(
       path => $file->stringify,
       name => $file->basename,
    );
    $p->read_magic_markers();

    is($p->{family}, 'magic', '"family" magic marker is read');
    is_deeply($p->{capabilities}, { suggest => 1, autoconf => 1, other => 1 },
        '"capabilities" magic marker is read');
}
SKIP: {
    skip 'Directory::Scratch not available', 2
        unless FOUND_DIRECTORY_SCRATCH;

    my $file = Directory::Scratch->new->touch('foo/bar/baz', <<'EOF');
# Munin test plugin.   Does nothing, just contains magic markers
#
# #%# capabilities=autoconf suggest other
EOF
    my $p = Munin::Node::Configure::Plugin->new(
       path => $file->stringify,
       name => $file->basename,
    );
    $p->read_magic_markers();

    is($p->{family}, 'contrib', 'Plugin family defaults to "contrib"');
    is_deeply($p->{capabilities}, { suggest => 1, autoconf => 1, other => 1 },
        '"capabilities" magic marker is read');

}


### parse_autoconf_response
{
    my @tests = (
        [ [ 'yes' ],                      [ 'yes' ],                      'Autoconf replied yes'                            ],
        [ [ 'no' ],                       [ 'no' ],                       'Autoconf replied no'                             ],
        [ [ 'no (just a test plugin) ' ], [ 'no', 'just a test plugin' ], 'Autoconf replied no with reason'                 ],
        [ [ 'oui' ],                      [ 'no' ],                       'Autoconf does not contain a recognised response' ],
        [ [ ],                            [ 'no' ],                       'Autoconf response was empty'                     ],
        [ [ 'yes', 'this is an error' ],  [ 'no' ],                       'Autoconf replied yes but with cruft'             ],
    );

    foreach (@tests) {
        my ($in, $expected, $msg) = @$_;
        my $p = gen_plugin('memory');

        $p->parse_autoconf_response(@$in);
        is($p->{default}, $expected->[0], "$msg - default");
        is($p->{defaultreason}, $expected->[1], "$msg - reason");
    }
}


### parse_suggest_response
{
    my @tests = (
        [ [qw/one two three/],       [qw/one two three/], 'Good suggestions'                   ],
        [ [],                        [],                  'No suggestions'                     ],
        [ [qw{one ~)(*&^%$£"!?/'/}], [qw/one/],           'Suggestion with illegal characters' ],
    );

    foreach (@tests) {
        my ($in, $expected, $msg) = @$_;
        my $p = gen_plugin('if_');

        $p->parse_suggest_response(@$in);
        is_deeply($p->{suggestions}, $expected, $msg);
    }
}


### parse_snmpconf_response

# helper function
sub run_snmpconf_tests
{
    my ($plugin_name, $test, $expected_error_count_key) = @_;

    my ($in, $expected, $errors, $msg) = @$test;

    my $p =       gen_plugin($plugin_name);
    my $p_clean = gen_plugin($plugin_name);

    $p->parse_snmpconf_response(@$in);

    is_deeply(delete $p->{table},       $expected->{table},       "$msg - table");
    is_deeply(delete $p->{require_oid}, $expected->{require_oid}, "$msg - required_oid");
    is_deeply(delete $p->{index},       $expected->{index},       "$msg - index");

    is(
        scalar(@{$p->{errors}}),
        $errors->{$expected_error_count_key},
        "$msg - expected number of errors - $expected_error_count_key"
    ) or diag("errors were: '@{$p->{errors}}'");

    # reset the errors
    $p->{errors} = [];

    is_deeply($p, $p_clean, 'plugin is otherwise unchanged');

    return;
}


{
    my @tests = (
        [
            [ 'require 1.3.6.1.2.1.25.2.2.0'   ],
            { require_oid => [ [ '1.3.6.1.2.1.25.2.2.0', undef ] ] },
            { single_errors => 0, double_errors => 1, },
            'Require - OID'
        ],
        [
            [ 'require .1.3.6.1.2.1.25.2.2.0' ],
            {require_oid => [['.1.3.6.1.2.1.25.2.2.0', undef],],},
            { single_errors => 0, double_errors => 1, },
            'Require - OID with leading dot'
        ],
        [
            [ 'require 1.3.6.1.2.1.25.2.2.0  [0-9]' ],
            {require_oid => [['1.3.6.1.2.1.25.2.2.0', '[0-9]'],],},
            { single_errors => 0, double_errors => 1, },
            'Require - OID with regex'
        ],
        [
            [ 'require 1.3.6.1.2.1.2.2.1.5.   [0-9]' ],
            {table => [['1.3.6.1.2.1.2.2.1.5', '[0-9]'],],},
            { single_errors => 0, double_errors => 1, },
            'Require - OID root with regex'
        ],
        [
            [ 'require 1.3.6.1.2.1.2.2.1.5.', ],
            {table => [['1.3.6.1.2.1.2.2.1.5', undef],],},
            { single_errors => 0, double_errors => 1, },
            'Require - OID root without regex'
        ],
        [
            [
                'require 1.3.6.1.2.1.2.2.1.5.  [0-9]',
                'require 1.3.6.1.2.1.2.2.1.10.  ',
                'require 1.3.6.1.2.1.2.2.2.5   2',
            ],
            {
                table => [
                    [ '1.3.6.1.2.1.2.2.1.5', '[0-9]' ],
                    [ '1.3.6.1.2.1.2.2.1.10', undef  ],
                ],
                require_oid => [
                    [ '1.3.6.1.2.1.2.2.2.5', '2' ],
                ],
            },
            { single_errors => 0, double_errors => 1, },
            'Require - Multiple require statements'
        ],
        [
            [ 'number  1.3.6.1.2.1.2.1.0', ],
            {},
            { single_errors => 1, double_errors => 2, },
            'Number - OID'
        ],
        [
            [ 'number  1.3.6.1.2.1.2.1.', ],
            {},
            { single_errors => 1, double_errors => 2, },
            'Number - OID root is an error'
        ],
        [
            [ 'index 1.3.6.1.2.1.2.1.0', ],
            {},
            { single_errors => 1, double_errors => 2, },
            'Index - OID is an error'
        ],
        [
            [ 'index   1.3.6.1.2.1.2.1.', ],
            {
                index => '1.3.6.1.2.1.2.1',
                table => [
                    [ '1.3.6.1.2.1.2.1' ]
                ],
            },
            { single_errors => 1, double_errors => 0, },
            'Index - OID root'
        ],
        [
            [
                'index  1.3.6.1.2.1.2.2.0.',
                'number 1.3.6.1.2.1.2.1.0  ',
                '', # blank line
                'require 1.3.6.1.2.1.2.2.2.5',
            ],
            {
                require_oid => [
                    ['1.3.6.1.2.1.2.2.2.5', undef ],
                ],
                index => '1.3.6.1.2.1.2.2.0',
                table => [
                    [ '1.3.6.1.2.1.2.2.0' ]
                ],
            },
            { single_errors => 2, double_errors => 1, },
            'Putting it all together'
        ],

        # TODO: badly formatted input
    );

    foreach (@tests) {
        # single-wildcard plugin
        run_snmpconf_tests('snmp__memory', $_, 'single_errors');
        # double-wildcard plugin
        run_snmpconf_tests('snmp__if_', $_, 'double_errors');
    }
}

### log_error
{
    my $p = gen_plugin('memory');

    is_deeply([ @{$p->{errors}} ], [], 'Plugins have no errors by default');

    $p->log_error('Faking it');
    is_deeply([ @{$p->{errors}} ], [ 'Faking it' ], 'Added an error');

    $p->log_error("Doing it wrong\n");
    is_deeply([ @{$p->{errors}} ], [ 'Faking it', 'Doing it wrong' ], 'Added an error with a trailing newline');
}
