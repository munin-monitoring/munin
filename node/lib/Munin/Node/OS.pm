package Munin::Node::OS;

use warnings;
use strict;

use Carp;
use English qw(-no_match_vars);
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


sub reap_child_group {
    my ($class, $child_pid) = @_;

    return unless $child_pid;
    return unless $class->possible_to_signal_process($child_pid);
    
    # Negative number signals the process group
    kill -1, $child_pid; 
    sleep 2; 
    kill -9, $child_pid;
}


sub possible_to_signal_process {
    my ($class, $pid) = @_;

    return kill (0, $pid);
}


sub set_effective_user_id {
    my ($class, $uid) = @_;

    $class->_set_xid(\$EFFECTIVE_USER_ID, $uid);
}


sub set_real_user_id {
    my ($class, $uid) = @_;

    $class->_set_xid(\$REAL_USER_ID, $uid);
}


sub set_effective_group_id {
    my ($class, $gid) = @_;

    $class->_set_xid(\$EFFECTIVE_GROUP_ID, $gid);
}


sub set_real_group_id {
    my ($class, $gid) = @_;

    $class->_set_xid(\$REAL_GROUP_ID, $gid);
}


sub _set_xid {
    my ($class, $x, $id) = @_;
    
    # According to pervar manpage, assigning to $<, $> etc results in
    # a system call. So we need to check $! for errors.
    $! = undef;
    $$x = $id;
    croak $! if $!;
}


1;

__END__

=head1 NAME

Munin::Node::OS - OS related utility methods for the munin node.


=head1 SYNOPSIS

 use Munin::Node::OS;
 my $uid  = Munin::Node::OS->get_uid('foo');
 my $host = Munin::Node::OS->get_fq_hostname();

=head1 METHODS

=over

=item B<get_uid>

 $uid = $class->get_uid($user)

Returns the user ID. $user might either be a user name or a user
ID. Returns undef if the user is nonexistent.

=item B<get_gid>

 $gid = $class->get_gid($group)

Returns the group ID. $group might either be a group name or a group
ID. Returns undef if the group is nonexistent.

=item B<get_fq_hostname>

 $host = $class->get_fq_hostname()

Returns the fully qualified host name of the machine.

=item B<check_perms>

 $bool = $class->check_perms($target);

FIX

=item B<reap_child_group>

 $class->reap_child_group($pid);

FIX

Sleeps for 2 seconds.

=item B<possible_to_signal_process>

FIX

=item B<set_effective_user_id>

FIX

=item B<set_effective_group_id>

FIX

=item B<set_real_user_id>

FIX

=item B<set_real_group_id>

FIX 

=back

=cut
