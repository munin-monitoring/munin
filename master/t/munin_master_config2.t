# -*- cperl -*-
use warnings;
use strict;

use Test::More tests => 24;
# use Test::More qw(no_plan);

use_ok('Munin::Master::Config');

# Get a empty class variable so we can test some class functions alone
my $c = bless { }, 'Munin::Master::Config';

# Test class


		  my $tc = "Prefix/keyword combos ";


is ( $c->_concat_config_line('Group;','port','4949'),
     'Group;port', $tc.'1');

is ( $c->_concat_config_line('Group;','Host.port','4949'),
     'Group;Host.port', $tc.'2');

is ( $c->_concat_config_line('Group;Host','port','4949'),
     'Group;Host.port', $tc.'3' );

is ( $c->_concat_config_line('Group;Host','service.port','4949'),
     'Group;Host:service.port', $tc.'4' );

is ( $c->_concat_config_line('Group;Host:service','port','4949'),
     'Group;Host:service.port', $tc.'5' );



	    $tc = "Prefix/keyword combos, nested groups ";


is ( $c->_concat_config_line('Group;','Group2;Host.port','4949'),
     'Group;Group2;Host.port', $tc.'1');

is ( $c->_concat_config_line('Group;Group2;','Host.port','4949'),
     'Group;Group2;Host.port', $tc.'2');

is ( $c->_concat_config_line('Group;Group2;Host','port','4949'),
     'Group;Group2;Host.port', $tc.'3' );

is ( $c->_concat_config_line('Group;Group2;Host','service.port','4949'),
     'Group;Group2;Host:service.port', $tc.'4' );

is ( $c->_concat_config_line('Group;Group2;Host:service','port','4949'),
     'Group;Group2;Host:service.port', $tc.'5' );



	   $tc = "Prefix/keyword combos, nested services ";


is ( $c->_concat_config_line('Group;','Host:service:service2.port','4949'),
     'Group;Host:service:service2.port', $tc.'1' );

is ( $c->_concat_config_line('Group;Host','service:service2.port','4949'),
     'Group;Host:service:service2.port', $tc.'2' );

is ( $c->_concat_config_line('Group;Host:service',':service2.port','4949'),
     'Group;Host:service:service2.port', $tc.'3' );

is ( $c->_concat_config_line('Group;Host:service:service2','port','4949'),
     'Group;Host:service:service2.port', $tc.'4' );



     $tc = "Prefix/keyword combos, nested groups and services ";


is($c->_concat_config_line('Group;','Group2;Host:service:service2.port','4949'),
    'Group;Group2;Host:service:service2.port', $tc.'1' );

is($c->_concat_config_line('Group;Group2;','Host:service:service2.port','4949'),
     'Group;Group2;Host:service:service2.port', $tc.'2' );

is($c->_concat_config_line('Group;Group2;Host','service:service2.port','4949'),
     'Group;Group2;Host:service:service2.port', $tc.'3' );

is($c->_concat_config_line('Group;Group2;Host:service',':service2.port','4949'),
    'Group;Group2;Host:service:service2.port', $tc.'4' );

is( $c->_concat_config_line('Group;Group2;Host:service:service2','port','4949'),
     'Group;Group2;Host:service:service2.port', $tc.'5' );



$tc = "Prefix/keyword combos, various service.field.keyword combinations ";


is ( $c->_concat_config_line('Group;','Host:service.field.max','4949'),
     'Group;Host:service.field.max', $tc.'1' );

is ( $c->_concat_config_line('Group;Host','service.field.max','4949'),
     'Group;Host:service.field.max', $tc.'2' );

is ( $c->_concat_config_line('Group;Host:service','field.max','4949'),
     'Group;Host:service.field.max', $tc.'3' );

is ( $c->_concat_config_line('Group;Host:service.field','max','4949'),
     'Group;Host:service.field.max', $tc.'4' );

# Alright, can anyone think of any more tests?
