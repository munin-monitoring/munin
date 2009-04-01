package Munin::Node::Service;

use warnings;
use strict;

use Munin::Node::Config;


my $config = Munin::Node::Config->instance();


sub is_a_runnable_service {
    my ($class, $file) = @_;
    
    my $path = "$config->{servicedir}/$file";

    return unless -f $path && -x _;

    # FIX isn't it enough to check that the file is executable and not
    # in 'ignores'? Can hidden files and config files be
    # unintantionally executable? What does config files do in the
    # service directory? Shouldn't we complain if there is junk in the
    # service directory?
    return if $file =~ m/^\./;               # Hidden files
    return if $file =~ m/.conf$/;            # Config files

    return if $file !~ m/^([-\w.]+)$/;       # Skip if any weird chars
    $file = $1;                              # Not tainted anymore.

    foreach my $regex (@{$config->{ignores}}) {
        return if $file =~ /$regex/;
    }
    
    return 1;
}


1;

__END__


=head1 NAME

Munin::Node::Service - Methods related to handling of Munin services


=head1 SYNOPSIS


 my $bool = Munin::Node::Service->is_a_runnable_service($file_name);


=head1 METHODS

=over

=item B<is_a_runnable_service>

 my $bool = Munin::Node::Service->is_a_runnable_service($file_name);

Runs miscellaneous tests on $file_name. These tests is intended to
verify that $file_name is a runnable service.

=back
