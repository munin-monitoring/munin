use warnings;
use strict;

package Munin::OS;


sub get_uid {
    my ($class, $user) = @_;
    return unless defined $user;
    return $user =~ /\d+/ ? $user : getpwnam($user);
}


sub get_gid {
    my ($class, $group) = @_;
    return unless defined $group;
    return $group =~ /\d+/ ? $group : getgrnam($group);
}


sub get_fq_hostname {
    my $hostname = eval {
        require Sys::Hostname;
        return (gethostbyname(Sys::Hostname::hostname()))[0];
    };
    return $hostname if $hostname;

    $hostname = `hostname`;
    chomp($hostname);
    $hostname =~ s/\s//g;
    return $hostname;
}


#FIX needs a better name
sub check_perms {
    my ($class, $target, $paranoia) = @_;
    my @stat;

    #FIX read paranoia from config

    return unless defined $target;
    return 1 unless $paranoia;

    unless (-e "$target")    {
	warn "Failed to check permissions on nonexistant target: '$target'";
	return;
    }

    my ($mode, $uid, $gid) = (stat $target)[2,4,5];
    if ($uid != 0 || ($gid != 0 && ($mode & oct(20))) || ($mode & oct(2))) {
	warn sprintf(
            "Warning: '$target' has dangerous permissions (%04o)",
            $mode & oct(7777),
        );
	return;
    }

    # Check dir as well
    if (-f "$target") {
	(my $dirname = $target) =~ s/[^\/]+$//;
	return $class->check_perms($dirname);
    }

    return 1;
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

=item $host = $class->get_fq_hostname()

Returns the fully qualified host name of the machine.

=item $bool = $class->check_perms($target, $paranoia);

FIX

=cut
