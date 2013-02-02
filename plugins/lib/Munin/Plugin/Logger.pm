package Munin::Plugin::Logger;
use base 'Munin::Common::Logger';

use strict;
use warnings;
use Munin::Plugin;

my $singleton;

sub new {
    my $class = shift;
    my $identity = sprintf( "plugin/%s", $Munin::Plugin::me );

    $singleton ||= $class->SUPER::new( { identity => $identity } );
    return $singleton;
}

1;
