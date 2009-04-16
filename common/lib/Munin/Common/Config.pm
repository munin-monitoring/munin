package Munin::Common::Config;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);


sub parse_config_from_file {
    my ($self, $config_file) = @_;

    $config_file ||= $self->{config_file};

    open my $file, '<', $config_file
        or croak "Cannot open '$config_file': $OS_ERROR";

    eval {
        $self->parse_config($file);
    };
    if ($EVAL_ERROR) {
        croak "Failed to parse config file '$config_file': $EVAL_ERROR";
    }
    
    close $file
        or croak "Cannot close '$config_file': $OS_ERROR";;

}


sub _trim {
    my $class = shift;
    
    chomp $_[0];
    $_[0] =~ s/^\s+//;
    $_[0] =~ s/\s+$//;

    return;
}


sub _strip_comment {
    my $class = shift;
    
    $_[0] =~ s/#.*//;
    
    return;
}


sub _parse_bool {
    my ($class, $str) = @_;

    return $str =~ m{\A no|false|off|0 \z}xms ? 0 : 1;
}


1;


__END__

=head1 NAME

Munin::Common::Config - Abstract base class for common config code.

=head1 SYNOPSIS

Don't use it directly. See L<Munin::Master::Config> and L<Munin::Node::Config>.

=head1 METHODS

=over

=item B<parse_config_from_file>

 $config->parse_config_from_file($file_name);

Parses the configuration in $file_name.

=back

