package Munin::Common::Utils;

use strict;
use warnings;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT_OK = qw( is_valid_hostname );

use Params::Validate qw( :all );

### Set operations #############################################################

sub is_valid_hostname {
    my ($hostname) = validate_pos(@_, { type => SCALAR } );

    # anything?
    return unless $hostname;

    # total length
    return if length($hostname) > 255;

    # each part
    my @parts = (split(/[.]/, $hostname));
    return if grep { length > 63 } @parts;
    return if grep { ! /^[a-z0-9\-]+$/ } @parts;

    return $hostname;

}

sub dump_to_file
{
	my ($filename, $obj) = @_;
	open(my $DUMPFILE, q{>>}, "$filename");

	print $DUMPFILE Dumper($obj);

	close($DUMPFILE);
}



1;

__END__


=head1 NAME

Munin::Common::Utils - Various utility functions


=head1 SYNOPSIS

  use Munin::Common::Utils qw( ... );


=head1 SUBROUTINES

=over

=item B<is_valid_hostname($hostname)>

Returns $hostname if it is syntactically valid, or an undef if not.

=back

=cut
