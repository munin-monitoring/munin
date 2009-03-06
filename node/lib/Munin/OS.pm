use warnings;
use strict;

package Munin::OS;


sub get_uid {
    my ($class, $user) = @_;
    return unless defined $user;
    return $user =~ /\d/ ? $user : getpwnam($user);
}


sub get_gid {
    my ($class, $group) = @_;
    return unless defined $group;
    return $group =~ /\d/ ? $group : getgrnam($group);
}

1;

__END__

=head1 NAME

Munin::OS - FIX


=head1 SYNOPSIS

FIX


=head1 METHODS

=over

=item $uid = $class->get_uid($user)

Returns the user ID. $user might either be a user name or a user ID.

=item $gid = $class->get_gid($group)

Returns the group ID. $group might either be a group name or a group ID.

=cut
