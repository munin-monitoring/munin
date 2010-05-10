use strict;
use warnings;

use Test::More 'no_plan';

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


### new
{
    my $plugin = new_ok('Munin::Node::Configure::Plugin' => [
        path => '/usr/share/munin/plugins/memory',
        name => 'memory'
    ], 'Simple plugin');
    my $wcplugin = new_ok('Munin::Node::Configure::Plugin' => [
        path => '/usr/share/munin/plugins/if_',
        name => 'if_'
    ], 'Wildcard plugin');
}


### is_wildcard
{
    my $p = gen_plugin('memory');
    ok(! $p->is_wildcard, 'Non-wildcard plugin is identfied as such');

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
{
    my $p = gen_plugin('snmpv3__memory');
    ok($p->is_snmp, 'Version 3 SNMP plugin is SNMP');
}
{
    my $p = gen_plugin('snmpv3__if_err_');
    ok($p->is_snmp, 'Wildcard version 3 SNMP plugin is SNMP');
}

exit;

### is_installed
{
    my $p = gen_plugin('memory');
    my $wcp = gen_plugin('if_');

    is($p->is_installed,   'no', 'Not installed by default');
    is($wcp->is_installed, 'no', 'Not installed by default (wildcard)');

    $p->add_instance('memory');
    is($p->is_installed, 'yes', 'Installed after instance is added');

    $wcp->add_instance('if_eth0');
    is($wcp->is_installed, 'yes', 'Installed after instance is added (wc)');
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
        'SNMP plugin - reduce'
    );
    is(
        $p->_expand_wildcard([ 'switch.example.com' ]),
        'snmp_switch.example.com_load',
        'Version 3 SNMP plugin - expand'
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

    my $same = \&Munin::Node::Configure::Plugin::_same;
    my $add = \&Munin::Node::Configure::Plugin::_add;
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
    is($p->suggestion_string, 'no', 'Suggestion string - no');

    $p->parse_autoconf_response('no (not a good idea)');
    is($p->suggestion_string, 'no [not a good idea]',
       'Suggestion string - no with reason');

    $p->parse_autoconf_response('yes');
    is($p->suggestion_string, 'yes', 'Suggestion string - yes');

    $p = gen_plugin('if_');

    $p->parse_autoconf_response('no');
    is($p->suggestion_string, 'no', 'Suggestion string - no');

    $p->parse_autoconf_response('no (not a good idea)');
    is($p->suggestion_string, 'no [not a good idea]',
       'Suggestion string - no with reason');

    $p->parse_autoconf_response('yes');
    is($p->suggestion_string, 'yes', 'Suggestion string - yes');

    $p->parse_suggest_response(qw/alpha bravo charlie/);
    is($p->suggestion_string, 'yes (+alpha +bravo +charlie)',
       'Suggestion string - yes with plugins to add');

    $p->add_instance('alpha');
    is($p->suggestion_string, 'yes (alpha +bravo +charlie)',
       'Suggestion string - yes with plugins to add and unchanged');

    $p->add_instance('delta');
    is($p->suggestion_string, 'yes (alpha +bravo +charlie -delta)',
       'Suggestion string - yes with plugins to add, remove and unchanged');
}


### installed_services_string
{
    my $p = gen_plugin('memory');
    is($p->installed_services_string, '', 'No services installed');
    $p->add_instance('memory');
    is($p->installed_services_string, '', 'One service installed');

    my $wcp = gen_plugin('if_');
    is($wcp->installed_services_string, '', 'No wildcard services installed');
    $wcp->add_instance('if_eth0');
    is($wcp->installed_services_string, 'eth0', 'One wildcard service installed');
    $wcp->add_instance('if_eth1');
    is($wcp->installed_services_string, 'eth0 eth1', 'Several wildcard service installed');

    # FIXME: snmp plugins
    my $sp = gen_plugin('snmp__load');
    my $swcp = gen_plugin('snmp__if_');

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
    my $wcp = gen_plugin('if_');

    is_deeply($wcp->_installed_links, [], 'no links by default');
    is_deeply($wcp->_installed_wild , [], 'no wildcards by default');
    is_deeply($wcp->_suggested_links, [], 'no suggestions by default');
    is_deeply($wcp->_suggested_wild , [], 'no suggested wildcards by default');

    $wcp->{default} = 'yes';  # it's ok to run it now
    $wcp->add_instance('if_eth0');
    is_deeply($wcp->_installed_links, ['if_eth0'], 'one link installed');
    is_deeply($wcp->_installed_wild , ['eth0'],    'one wildcard');

    $wcp->add_instance('if_eth1');
    is_deeply($wcp->_installed_links, [qw/if_eth0 if_eth1/], 'two links installed');
    is_deeply($wcp->_installed_wild , [qw/eth0 eth1/],       'two wildcards');

    $wcp->parse_suggest_response('eth2');
    is_deeply($wcp->_suggested_links, [ 'if_eth2' ], 'with a suggestion');
    is_deeply($wcp->_suggested_wild , [ 'eth2' ],    'with a suggested wildcard');
}
{
    my $sp = gen_plugin('snmp__load');

    $sp->{default} = 'yes';  # it's ok to run it now
    $sp->add_instance('snmp_switch.example.com_load');
    is_deeply($sp->_installed_links, ['snmp_switch.example.com_load'], 'one link installed');
    is_deeply($sp->_installed_wild , ['switch.example.com'],           'one wildcard');
    $sp->add_instance('snmp_switch2.example.com_load');
    is_deeply($sp->_installed_links,
                [qw/snmp_switch.example.com_load snmp_switch2.example.com_load/],
                'two links installed');
    is_deeply($sp->_installed_wild , [qw/switch.example.com switch2.example.com/], 'two wildcards');

    push @{$sp->{suggestions}}, [ 'switch.example.com' ];
    is_deeply($sp->_suggested_links, [ 'snmp_switch.example.com_load' ], 'with a suggestion');
    is_deeply($sp->_suggested_wild , [ 'switch.example.com' ],    'with a suggested wildcard');
}
{
    my $swcp = gen_plugin('snmp__if_');

    $swcp->{default} = 'yes';  # it's ok to run it now
    $swcp->add_instance('snmp_switch.example.com_if_1');
    is_deeply($swcp->_installed_links, ['snmp_switch.example.com_if_1'], 'one link installed');
    is_deeply($swcp->_installed_wild , ['switch.example.com/1'],         'one wildcard');
    $swcp->add_instance('snmp_switch.example.com_if_2');
    is_deeply($swcp->_installed_links,
                [qw/snmp_switch.example.com_if_1 snmp_switch.example.com_if_2/],
                'two links installed');
    is_deeply($swcp->_installed_wild , [qw{switch.example.com/1 switch.example.com/2}], 'two wildcards');

    push @{$swcp->{suggestions}}, [ 'switch.example.com', '1' ];
    is_deeply($swcp->_suggested_links, [ 'snmp_switch.example.com_if_1' ], 'with a suggestion');
    is_deeply($swcp->_suggested_wild , [ 'switch.example.com/1' ],    'with a suggested wildcard');
    undef $swcp;
}


### services_to_add
### services_to_remove
{
    # not installed and shouldn't be
    my $p = gen_plugin('memory');

    is_deeply([ $p->services_to_add    ], []);
    is_deeply([ $p->services_to_remove ], []);

    # not installed and should be
    $p = gen_plugin('memory');
    $p->parse_autoconf_response('yes');

    is_deeply([ $p->services_to_add    ], ['memory']);
    is_deeply([ $p->services_to_remove ], []);

    # installed and should be
    $p = gen_plugin('memory');
    $p->parse_autoconf_response('yes');
    $p->add_instance('memory');

    is_deeply([ $p->services_to_add    ], []);
    is_deeply([ $p->services_to_remove ], []);

    # installed and shouldn't be
    $p = gen_plugin('memory');
    $p->parse_autoconf_response('no');
    $p->add_instance('memory');

    is_deeply([ $p->services_to_add    ], []);
    is_deeply([ $p->services_to_remove ], ['memory']);


    my $wcp = gen_plugin('if_');

    # suggestions to be removed

    # suggestions to be added

    # suggestions are already correct

}


### read_magic_markers
SKIP: {
    skip 'Directory::Scratch not installed' unless FOUND_DIRECTORY_SCRATCH;

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
    skip 'Directory::Scratch not available' unless FOUND_DIRECTORY_SCRATCH;

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
        [ [ 'yes' ], [ 'yes' ], 'Autoconf replied yes' ],
        [ [ 'no' ],  [ 'no' ], 'Autoconf replied no' ],
        [ [ 'no (just a test plugin) ' ], [ 'no', 'just a test plugin' ], 'Autoconf replied no with reason' ],
        [ [ 'oui' ], [ 'no' ], 'Autoconf doesnt contain a recognised response' ],
        [ [ ], [ 'no' ], 'Autoconf response was empty' ],
        [ [ 'yes', 'this is an error' ], [ 'no' ], 'Autoconf replied yes but with cruft' ],
#       [ [ ], [ ], '' ],
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
        [ [ qw/one two three/ ], [ qw/one two three/ ], 'Good suggestions' ],
        [ [ ], [ ], 'No suggestions' ],
        [ [ qw{one ~)(*&^%$£"!?/'/} ], [ qw/one/ ], 'Suggestion with illegal characters' ],
    );

    foreach (@tests) {
        my ($in, $expected, $msg) = @$_;
        my $p = gen_plugin('if_');

        $p->parse_suggest_response(@$in);
        is_deeply($p->{suggestions}, $expected, $msg);
    }
}

### parse_snmpconf_response


### log_error



# vim: sw=4 : ts=4 : expandtab
