use warnings;
use strict;

use English qw(-no_match_vars);
use Test::MockModule;
use Test::More tests => 1;
use File::Temp qw( tempdir );

use Test::MockObject;

# Faking RRDs.pm, as we don't really need it
my $mock = Test::MockObject->new();
$mock->fake_module( 'RRDs',
	'create' => sub { },
	'error' => sub { },
);

use_ok('Munin::Master::Update');

use Munin::Common::Defaults;

my $config = Munin::Master::Config->instance()->{config};
$config->{dbdir} = tempdir(CLEANUP => 1);

# Make 'keys' return the keys in sorted order.
package Munin::Master::Update;
use subs 'keys';
package main;
*Munin::Master::Update::keys = sub {
    my %hash = @_;
    sort(CORE::keys(%hash));
};

#
sub remove_indentation {
    my ($str) = @_;

    $str =~ s{\n\ *}{\n}xmsg;
    $str =~ s{\A \n }{}xms;

    return $str;
}

#
my $mockconfig = Test::MockModule->new('Munin::Master::Config');
$mockconfig->mock(get_groups_and_hosts => sub { return () });

# TODO - Test the storable implem
