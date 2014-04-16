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
    $message =~ s{^\[(DEBUG|INFO|NOTICE|WARNING|ERROR)\][\s:]*}{};
    return $message;
}


my $screen_format = sub {
    my %args    = @_;
    my $level   = $args{level};
    my $message = $args{message};

    $message = _remove_label($message);

    chomp $message;

    return sprintf( "%s [%s]: %s\n", _timestamp, $level, $message );
};

my $syslog_format = sub {
    my %args    = @_;
    my $level   = $args{level};
    my $message = $args{message};

    $message = _remove_label($message);

    chomp $message;

    return $message;
};

my $log ||= Log::Dispatch->new();

use Log::Dispatch::Screen;
$log->add(
    Log::Dispatch::Screen->new(
        min_level => 'error',
        name => 'screen',
        callbacks => $screen_format
    )
);

use Log::Dispatch::Syslog;
$log->add(
    Log::Dispatch::Syslog->new(
        name => 'syslog',
        min_level => 'debug',
        callbacks => $syslog_format,
    )
);

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

   DEBUG("blah, blah, blah");
   INFO("blah, blah, blah");
   NOTICE("blah, blah, blah");
   WARNING("blah, blah, blah");
   ERROR("blah, blah, blah");
   CRITICAL("blah, blah, blah");
   ALERT("blah, blah, blah");
   EMERGENCY("oops");
   LOGCROAK("Goodbye, world!");

=head1 DESCRIPTION

Munin::Common::Logger handles logging for Munin.

It uses Log::Dispatch for this, and exports utility functions to enable
logging from other parts of Munin.

To help transition from previous logging modules:

=over

=item  Functions are similar to Log4perl

The functions used are similar to Log4perl, to make the number of code changes
minimal.

=item  Log messages are changed

The "[SEVERITY]" prefix in the existing log messages are removed by
Munin::Common::Logger. Severity is set by the function used to log,
and used in the output formatting.

=back

=head2 EXPORT

The functions DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT,
EMERGENCY and LOGCROAK are exported by default.

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
