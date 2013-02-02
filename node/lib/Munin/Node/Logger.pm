package Munin::Node::Logger;
use base 'Munin::Common::Logger';

use strict;
use warnings;

my $singleton;

sub new {
    my $class = shift;
    $singleton ||= $class->SUPER::new( { identity => 'node' } );
    return $singleton;
}

1;
