# -*- cperl -*-
use warnings;
use strict;

use Test::More tests => 45;
# use Test::More qw(no_plan);

use_ok('Munin::Master::Config');

# Get a empty class variable so we can test some class functions alone
my $c = bless { }, 'Munin::Master::Config';

# Test class
my $tc;

		       $tc = "Simple basics ";

is ( $c->_concat_config_line('','htmldir','/foo/bar'),
     'htmldir', $tc.'1');

is ( $c->_concat_config_line('grouphere;lookfar.langfeldt.net:if_eth0','graph_args','--l 0 -base'),
     'grouphere;lookfar.langfeldt.net:if_eth0.graph_args', $tc.'2');

is ( $c->_concat_config_line('grouphere;lookfar.langfeldt.net:if_eth0','up.label','Spazz'),
     'grouphere;lookfar.langfeldt.net:if_eth0.up.label', $tc.'3');



		   $tc = "Settings at all levels ";

is ( $c->_concat_config_line('','address','127.0.0.1'),
     'address', $tc.'1');

is ( $c->_concat_config_line('Group;','address','127.0.0.1'),
     'Group;address', $tc.'2');

is ( $c->_concat_config_line('Group;Group2;','address','127.0.0.1'),
     'Group;Group2;address', $tc.'3');

is ( $c->_concat_config_line('Group;','Group2;address','127.0.0.1'),
     'Group;Group2;address', $tc.'4');

is ( $c->_concat_config_line('Group;Host.example.com','address','127.0.0.1'),
     'Group;Host.example.com:address', $tc.'5');

is ( $c->_concat_config_line('Group;','Host.example.com:address','127.0.0.1'),
     'Group;Host.example.com:address', $tc.'6');


is ( $c->_concat_config_line('Group;Group2;','Host.example.com:address','127.0.0.1'),
     'Group;Group2;Host.example.com:address', $tc.'7');

is ( $c->_concat_config_line('Group;','Group2;Host.example.com:address','127.0.0.1'),
     'Group;Group2;Host.example.com:address', $tc.'8');

is ( $c->_concat_config_line('Group;Group2;','graph_title','Test9'),
     'Group;Group2;graph_title', $tc.'9');

is ( $c->_concat_config_line('Group;Host.example.com','service.graph_title','Foo!'),
     'Group;Host.example.com:service.graph_title', $tc.'10');

is ( $c->_concat_config_line('Group;Host.example.com:service','graph_title','Foo!'),
     'Group;Host.example.com:service.graph_title', $tc.'11');

is ( $c->_concat_config_line('Group;Host.example.com','service.service2.graph_title','Foo!'),
     'Group;Host.example.com:service.service2.graph_title', $tc.'12');

is ( $c->_concat_config_line('Group;Host.example.com:service','service2.graph_title','Foo!'),
     'Group;Host.example.com:service.service2.graph_title', $tc.'13');

is ( $c->_concat_config_line('Group;Host.example.com:service.service2','graph_title','Foo!'),
     'Group;Host.example.com:service.service2.graph_title', $tc.'14');


		    $tc = "Implicit group names ";

is ( $c->_concat_config_line('foo.example.com','port','4949'),
     'example.com;foo.example.com:port', $tc.'1');

is ( $c->_concat_config_line('foo.example.com','address','4949'),
     'example.com;foo.example.com:address', $tc.'2');

is ( $c->_concat_config_line('foo.example.com','if_eth0.up.label','4949'),
     'example.com;foo.example.com:if_eth0.up.label', $tc.'3');

is ( $c->_concat_config_line('localhost','port','4949'),
     'localhost;localhost:port', $tc.'4');


		   $tc = "Prefix/keyword combos ";

is ( $c->_concat_config_line('Group;','port','4949'),
     'Group;port', $tc.'1');

is ( $c->_concat_config_line('Group;','Host.example.com:port','4949'),
     'Group;Host.example.com:port', $tc.'2');

is ( $c->_concat_config_line('Group;Host.example.com','port','4949'),
     'Group;Host.example.com:port', $tc.'3' );

is ( $c->_concat_config_line('Group;Host.example.com','service.port','4949'),
     'Group;Host.example.com:service.port', $tc.'4' );

is ( $c->_concat_config_line('Group;Host.example.com:service','port','4949'),
     'Group;Host.example.com:service.port', $tc.'5' );


	    $tc = "Prefix/keyword combos, nested groups ";

is ( $c->_concat_config_line('Group;','Group2;Host.example.com:port','4949'),
     'Group;Group2;Host.example.com:port', $tc.'1');

is ( $c->_concat_config_line('Group;Group2;','Host.example.com:port','4949'),
     'Group;Group2;Host.example.com:port', $tc.'2');

is ( $c->_concat_config_line('Group;Group2;Host.example.com','port','4949'),
     'Group;Group2;Host.example.com:port', $tc.'3' );

is ( $c->_concat_config_line('Group;Group2;Host.example.com','service.port','4949'),
     'Group;Group2;Host.example.com:service.port', $tc.'4' );

is ( $c->_concat_config_line('Group;Group2;Host.example.com:service','port','4949'),
     'Group;Group2;Host.example.com:service.port', $tc.'5' );



	   $tc = "Prefix/keyword combos, nested services ";


is ( $c->_concat_config_line('Group;','Host.example.com:service.service2.port','4949'),
     'Group;Host.example.com:service.service2.port', $tc.'1' );

is ( $c->_concat_config_line('Group;Host.example.com','service.service2.port','4949'),
     'Group;Host.example.com:service.service2.port', $tc.'2' );

is ( $c->_concat_config_line('Group;Host.example.com:service','service2.port','4949'),
     'Group;Host.example.com:service.service2.port', $tc.'3' );

is ( $c->_concat_config_line('Group;Host.example.com:service.service2','port','4949'),
     'Group;Host.example.com:service.service2.port', $tc.'4' );



     $tc = "Prefix/keyword combos, nested groups and services ";


is($c->_concat_config_line('Group;','Group2;Host.example.com:service.service2.port','4949'),
    'Group;Group2;Host.example.com:service.service2.port', $tc.'1' );

is($c->_concat_config_line('Group;Group2;','Host.example.com:service.service2.port','4949'),
     'Group;Group2;Host.example.com:service.service2.port', $tc.'2' );

is($c->_concat_config_line('Group;Group2;Host.example.com','service.service2.port','4949'),
     'Group;Group2;Host.example.com:service.service2.port', $tc.'3' );

is($c->_concat_config_line('Group;Group2;Host.example.com:service','service2.port','4949'),
    'Group;Group2;Host.example.com:service.service2.port', $tc.'4' );

is( $c->_concat_config_line('Group;Group2;Host.example.com:service.service2','port','4949'),
     'Group;Group2;Host.example.com:service.service2.port', $tc.'5' );



$tc = "Prefix/keyword combos, various service.field.keyword combinations ";


is ( $c->_concat_config_line('Group;','Host.example.com:service.field.max','4949'),
     'Group;Host.example.com:service.field.max', $tc.'1' );

is ( $c->_concat_config_line('Group;Host.example.com','service.field.max','4949'),
     'Group;Host.example.com:service.field.max', $tc.'2' );

is ( $c->_concat_config_line('Group;Host.example.com:service','field.max','4949'),
     'Group;Host.example.com:service.field.max', $tc.'3' );

is ( $c->_concat_config_line('Group;Host.example.com:service.field','max','4949'),
     'Group;Host.example.com:service.field.max', $tc.'4' );

# Alright, can anyone think of any more tests?
# Probably even more combinations of nesting in both ends to see if that
# somehow trips up the code.
