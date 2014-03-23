package Munin::Common::Logger;

use strict;
use warnings;

use Carp;

use Exporter;

our @ISA = qw(Exporter);

our @EXPORT =
  qw(DEBUG INFO NOTICE WARN WARNING ERROR CRITICAL FATAL ALERT EMERGENCY LOGCROAK);

use Log::Dispatch;
use POSIX;


sub _timestamp {
    return strftime( "%Y-%m-%d %H:%M:%S", localtime );
}

# This is for compatibility with old logging calls. This can safely be removed when all old logging
# calls have been updated.
sub _remove_label {
	my ($message) = @_;
	$message =~ s{^\[(DEBUG|INFO|NOTICE|WARNING|ERROR)\]\s*}{};
	return $message;
}


my $screen_format = sub {
    my %args    = @_;
    my $level   = $args{level};
    my $message = $args{message};

	$message = _remove_label($message);

	chomp $message;

    return sprintf( "%s [%s]: %s\n",
        _timestamp, $level, $message );
};

my $log ||=
  Log::Dispatch->new( outputs =>
      [ [ 'Screen', min_level => 'debug', callbacks => $screen_format ], ] );

sub DEBUG {
    my ($message) = @_;
    $log->debug($message);
}

sub INFO {
    my ($message) = @_;
    $log->info($message);
}

sub NOTICE {
    my ($message) = @_;
    $log->notice($message);
}

sub WARN {
    my ($message) = @_;
    $log->warning($message);
}

sub WARNING {
    my ($message) = @_;
    $log->warning($message);
}

sub ERROR {
    my ($message) = @_;
    $log->error($message);
}

sub CRITICAL {
    my ($message) = @_;
    $log->critical($message);
}

sub FATAL {
    my ($message) = @_;
    $log->critical($message);
}

sub ALERT {
    my ($message) = @_;
    $log->alert($message);
}

sub EMERGENCY {
    my ($message) = @_;
    $log->emergency($message);
}

sub LOGCROAK {
    my ($message) = @_;
    $log->log_and_croak( level => 'critical', message => $message );
}

1;
__END__

=head1 NAME

Munin::Common::Logger - Perl extension for blah blah blah

=head1 SYNOPSIS

   use Munin::Common::Logger;
   blah blah blah

=head1 DESCRIPTION

Stub documentation for Munin::Common::Logger,

Blah blah blah.

=head2 EXPORT

None by default.

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Stig Sandbeck Mathisen, E<lt>ssm@fnord.noE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Stig Sandbeck Mathisen

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=head1 BUGS

None reported... yet.

=cut
