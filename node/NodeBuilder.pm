package NodeBuilder;
use base qw(Module::Build);

use warnings;
use strict;

use lib '../common/lib';

use File::Spec;

sub new {
    my ($class, %args) = @_;

    $args{sbin_files} = { map {$_ => $_} Module::Build::Base->_files_in('sbin') };
    my $self = $class->SUPER::new(%args);
    push @{$self->{properties}{bindoc_dirs}}, 'blib/sbin';

    $self->install_path('sbin' => $self->install_destination('bin')."/../sbin/");

    #use Data::Dumper; warn Dumper($self);

    $self->add_build_element('sbin');

    return $self;
}

1;
