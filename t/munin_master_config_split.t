# -*- cperl -*-
use warnings;
use strict;

# This test-set does the reverse of munin_master_config_concat, but this is simpler
# because all variations of prefix/key combined in the concat function works out to
# one canonical format, which breaks down in a predictable manner.

use Test::More tests => 24;
# use Test::More qw(no_plan);

use_ok('Munin::Master::Config');

# Get a empty class variable so we can test some class functions alone
my $c = bless { }, 'Munin::Master::Config';

# Test class
my $tc;

		       $tc = "Simple basics ";

use Data::Dumper;

# print Dumper $c->_split_config_line('htmldir');

is_deeply ( [$c->_split_config_line('htmldir')], [[],'','htmldir'],$tc.'1');

is_deeply ( [ $c->_split_config_line('grouphere;lookfar.langfeldt.net:if_eth0.graph_args') ],
	    [['grouphere'],'lookfar.langfeldt.net','if_eth0.graph_args'],
	    $tc.'2');

is_deeply ( [ $c->_split_config_line('grouphere;lookfar.langfeldt.net:if_eth0.up.label') ],
	    [['grouphere'],'lookfar.langfeldt.net','if_eth0.up.label'],$tc.'3');


		   $tc = "Settings at all levels ";

is_deeply ( [ $c->_split_config_line('address') ],
	    [[],'','address'], $tc.'1');

is_deeply ( [ $c->_split_config_line('Group;address') ],
	    [['Group'],'','address'], $tc.'2');

is_deeply ( [ $c->_split_config_line('Group;Group2;address') ],
	    [ ['Group','Group2'],'','address'], $tc.'3');

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:address') ],
	    [['Group'],'Host.example.com','address'], $tc.'5');

is_deeply ( [ $c->_split_config_line('Group;Group2;Host.example.com:address') ],
	    [['Group','Group2'],'Host.example.com','address'], $tc.'7');

is_deeply ( [ $c->_split_config_line('Group;Group2;graph_title') ],
	    [['Group','Group2'],'','graph_title'], $tc.'9');

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:service.graph_title') ],
	    [['Group'],'Host.example.com','service.graph_title'], $tc.'10');

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:service.service2.graph_title') ],
	    [['Group'],'Host.example.com','service.service2.graph_title'], $tc.'12');


		    $tc = "Implicit group names ";

is_deeply ( [ $c->_split_config_line('example.com;foo.example.com:port') ],
	    [['example.com'],'foo.example.com','port'], $tc.'1');

is_deeply ( [ $c->_split_config_line('example.com;foo.example.com:address') ],
	    [['example.com'],'foo.example.com','address'], $tc.'2');

is_deeply ( [ $c->_split_config_line('example.com;foo.example.com:if_eth0.up.label') ],
	    [['example.com'],'foo.example.com','if_eth0.up.label'], $tc.'3');

is_deeply ( [ $c->_split_config_line('localhost;localhost:port') ],
	    [['localhost'],'localhost','port'], $tc.'4');


		   $tc = "Prefix/keyword combos ";

is_deeply ( [ $c->_split_config_line('Group;port') ] ,
	    [['Group'],'','port'], $tc.'1');

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:port')],
	    [['Group'],'Host.example.com','port'], $tc.'2');

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:service.port') ],
	    [['Group'],'Host.example.com','service.port'], $tc.'4' );


	    $tc = "Prefix/keyword combos, nested groups ";

is_deeply ( [ $c->_split_config_line('Group;Group2;Host.example.com:port') ],
	    [['Group','Group2'], 'Host.example.com', 'port'], $tc.'1');

is_deeply ( [ $c->_split_config_line('Group;Group2;Host.example.com:service.port') ],
	    [['Group','Group2'], 'Host.example.com', 'service.port'], $tc.'4' );


	   $tc = "Prefix/keyword combos, nested services ";

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:service.service2.port') ],
	    [['Group'],'Host.example.com','service.service2.port'], $tc.'1' );


     $tc = "Prefix/keyword combos, nested groups and services ";

is_deeply ( [ $c->_split_config_line('Group;Group2;Host.example.com:service.service2.port') ],
	    [['Group','Group2'],'Host.example.com','service.service2.port'], $tc.'1' );


$tc = "Prefix/keyword combos, various service.field.keyword combinations ";

is_deeply ( [ $c->_split_config_line('Group;Host.example.com:service.field.max') ],
	    [['Group'],'Host.example.com','service.field.max'], $tc.'1' );

# Alright, can anyone think of any more tests?
# Probably even more combinations of nesting in both ends to see if that
# somehow trips up the code.
