package NodeBuilder;

use base qw(Module::Build);

use warnings;
use strict;

use lib '../common/blib/lib';

use English qw(-no_match_vars);
use File::Spec;
use Munin::Common::Defaults;

sub new {
    my ($class, %args) = @_;

    $args{sbin_files} = { map {$_ => $_} Module::Build::Base->_files_in('sbin') };

    my $self = $class->SUPER::new(%args);
    #use Data::Dumper; warn Dumper($self);

    push @{$self->{properties}{bindoc_dirs}}, 'blib/sbin';
    $self->install_path('sbin' => $self->install_destination('bin')."/../sbin/");
    $self->add_build_element('sbin');

    return $self;
}


sub ACTION_docs {
    my ($self) = @_;

    $self->SUPER::ACTION_docs;
    my @files = (
        Module::Build::Base->_files_in('blib/bindoc'),
        Module::Build::Base->_files_in('blib/libdoc'),
    );

    #use Data::Dumper; warn Dumper(\@files);

    for my $file (@files) {
        open my $fh, '<', $file or die $OS_ERROR;
        my $contents = do { local $INPUT_RECORD_SEPARATOR; <$fh> };
        close $fh or die $OS_ERROR;

        $contents =~ s/@@([^@]+)@@/eval "\$Munin::Common::Defaults::MUNIN_$1"/eg;

        open $fh, '>', $file or die $OS_ERROR;
        print $fh $contents;
        close $fh or die $OS_ERROR;
    }
}


1;
