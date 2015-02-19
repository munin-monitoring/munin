package Munin::Common::Logger;

use strict;
use warnings;

use Carp;

use Exporter;
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::Syslog;

our @ISA = qw(Exporter);

our @EXPORT
    = qw(DEBUG INFO NOTICE WARN WARNING ERROR CRITICAL FATAL ALERT EMERGENCY LOGCROAK);

use Params::Validate qw(validate SCALAR);
use POSIX;

sub _program_name {
    my @path = split( '/', $0 );
    return $path[-1];
}

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

our $log ||= Log::Dispatch->new();

$log->add(
    Log::Dispatch::Screen->new(
        name      => 'default-screen',
        min_level => 'critical',
        callbacks => $screen_format
    )
);

$log->add(
    Log::Dispatch::Syslog->new(
        name      => 'default-syslog',
        ident     => _program_name,
        min_level => 'warning',
        callbacks => $syslog_format,
    )
);

sub _remove_default_logging {
    $log->remove('default-screen') if $log->output('default-screen');
    $log->remove('default-syslog') if $log->output('default-syslog');
}

sub _remove_configured_logging {
    $log->remove('configured') if $log->output('configured');
}

sub configure {
    my %p = validate(
        @_,
        {   output => {
                type    => SCALAR,
                default => 'syslog',
                regex   => qr/^(?:syslog|screen)$/
            },
            level => {
                type    => SCALAR,
                default => 'warning',
                regex =>
                    qr/^(?:debug|info|notice|warning|error|critical|alert|emergency)$/
            },
        }
    );

    _remove_default_logging;
    _remove_configured_logging;

    if ( $p{output} eq 'screen' ) {
        $log->add(
            Log::Dispatch::Screen->new(
                name      => 'configured',
                min_level => $p{level},
                callbacks => $screen_format
            )
        );
    }
    elsif ( $p{output} eq 'syslog' ) {
        $log->add(
            Log::Dispatch::Syslog->new(
                name      => 'configured',
                ident     => _program_name,
                min_level => $p{level},
                callbacks => $syslog_format,
            )
        );
    }

    return $log;
}

sub would_log {
    my ($level) = @_;
    return $log->would_log($level);
}

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

   DEBUG(slow_and_expensive_operation) if Munin::Common::Logger::would_log('debug');

   Munin::Common::Logger::configure( level => 'debug') if $debug;

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

=head1 FUNCTIONS

=over

=item configure { level => $level, output => $output }

  configure { level => 'error', output => 'screen'}

  configure { level => 'debug', output => 'syslog'}

Removes the default logging, and replaces it with the configured log output.

Option "level" sets the minimum log level. Takes one argument, which is the log level to accept.
Optional, default is "warning".

See L<Log::Dispatch> for a list of valid log levels.

Option "output" sets the log output. Valid outputs are 'screen' and 'syslog'. Optional, default is
"syslog".

=item would_log

Returns true if a message would be logged given the log level. Takes one argument, which is the log
level to check.

Use this around expensive log statements, to skip them if they would not be logged.

See L<Log::Dispatch> for a list of valid log levels.

=item DEBUG

Log with DEBUG priority. Takes one argument, which is the string to log.

=item INFO

Log with INFO priority. Takes one argument, which is the string to log.

=item NOTICE

Log with NOTICE priority. Takes one argument, which is the string to log.

=item WARN

Log with WARNING priority. Takes one argument, which is the string to log.

=item WARNING

Log with WARNING priority. Takes one argument, which is the string to log.

=item ERROR

Log with ERROR priority. Takes one argument, which is the string to log.

=item CRITICAL

Log with CRITICAL priority. Takes one argument, which is the string to log.

=item EMERGENCY

Log with EMERGENCY priority. Takes one argument, which is the string to log.

=item ALERT

Log with ALERT priority. Takes one argument, which is the string to log.

=item FATAL

Log with FATAL priority. Takes one argument, which is the string to log.

=item LOGCROAK

Log with CRITIAL priority exit the program. Takes one argument, which is the string to log.

See also C<log_and_croak> in L<Log::Dispatch>.

=back

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
