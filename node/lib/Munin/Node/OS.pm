package Munin::Node::OS;

use warnings;
use strict;

use Munin::Node::Config;
use POSIX;

sub get_uid {
    my ($class, $user) = @_;
    return $class->_get_xid($user, \&POSIX::getpwnam, \&POSIX::getpwuid);
}


sub get_gid {
    my ($class, $group) = @_;
    return $class->_get_xid($group, \&POSIX::getgrnam, \&POSIX::getgrgid);
}

sub _get_xid {
    my ($class, $entity, $name2num, $num2name) = @_;
    return unless defined $entity;

    if ($entity =~ /^\d+$/) {
        return unless $num2name->($entity); # Entity does not exist
        return $entity;
    } else {
        return $name2num->($entity);
    }
}


sub get_fq_hostname {
    my ($class) = @_;

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
    my ($class, $target) = @_;
    my @stat;

    my $config = Munin::Node::Config->instance();

    return unless defined $target;
    return 1 unless $config->{paranoia};

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

=item B<get_uid>

 $uid = $class->get_uid($user)

Returns the user ID. $user might either be a user name or a user ID.

=item B<get_gid>

 $gid = $class->get_gid($group)

Returns the group ID. $group might either be a group name or a group ID.

=item B<get_fq_hostname>

 $host = $class->get_fq_hostname()

Returns the fully qualified host name of the machine.

=item B<check_perms>

 $bool = $class->check_perms($target);

FIX

=cut
