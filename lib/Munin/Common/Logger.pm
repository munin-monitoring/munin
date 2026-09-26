package Munin::Common::Logger;

use strict;
use warnings;

use Carp;

use Exporter;
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use Log::Dispatch::Syslog;
use Munin::Common::Defaults;

our @ISA = qw(Exporter);

our @EXPORT
    = qw(DEBUG INFO NOTICE WARN ERROR CRITICAL FATAL ALERT EMERGENCY);

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
    $message =~ s{^\[(DEBUG|INFO|NOTICE|WARNING|ERROR|CRITICAL|FATAL|ALERT|EMERGENCY)\][\s:]*}{};
    return $message;
}


my $screen_format = sub {
    my %args    = @_;
    my $level   = $args{level};
    my $message = $args{message};

    $message = _remove_label($message) if $message =~ /^\[(DEBUG|INFO|NOTICE|WARNING|ERROR)\][\s:]*/;

    chomp $message;

    return sprintf( "%s [%s][%06d]: %s\n", _timestamp, $level, $$, $message );
};

my $file_format = $screen_format;

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
                regex   => qr/^(?:syslog|screen|file)$/
            },
            level => {
                type    => SCALAR,
                default => 'warning',
                regex =>
                    qr/^(?:debug|info|notice|warning|error|critical|alert|emergency)$/
            },
            logfile => {
                type    => SCALAR,
                default => '',
                regex   => qr/^\/.*$/
            },
            logdir => {
                type    => SCALAR,
                default => $Munin::Common::Defaults::MUNIN_LOGDIR,
                regex   => qr/^\/.*$/
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
    elsif ( $p{output} eq 'file' ) {
        $log->add(
            Log::Dispatch::File->new(
                name      => 'configured',
                filename  => $p{logfile} || ($p{logdir} . '/' . _program_name),
                mode      => 'append',
                min_level => $p{level},
                callbacks => $file_format,
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

# https://perldoc.perl.org/functions/caller
#  #   0         1          2      3            4
#  my ($package, $filename, $line, $subroutine, $hasargs,
#  #   5           6          7            8       9         10
#      $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash
#  ) = caller($i);

sub _whoami  {
# uncoverable subroutine
my @c = caller(1); return $c[3] . ":" . $c[2]
}

sub _whowasi {
    my @c = caller(2);
    return $c[3] . ":" . $c[2];
}

sub would_log {
    my ($level) = @_;
    return $log->would_log($level);
}

sub DEBUG {
    my ($message) = @_;
    # Also record the caller for DEBUG
    # It has a performance penaly, and is only useful when debugging anyway
    my $from = _whowasi();
    $log->debug("[$from] $message");
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



sub ERROR {
    # uncoverable subroutine
    my ($message) = @_;
    $log->error($message);
}

sub CRITICAL {
    # uncoverable subroutine
    my ($message) = @_;
    $log->critical($message);
}

sub FATAL {
    my ($message) = @_;
    $log->log_and_croak( level => 'critical', message => $message );
}

sub ALERT {
    # uncoverable subroutine
    my ($message) = @_;
    $log->alert($message);
}

sub EMERGENCY {
    # uncoverable subroutine
    my ($message) = @_;
    $log->emergency($message);
}



1;
__END__

=head1 NAME

Munin::Common::Logger - Perl extension for blah blah blah

=head1 SYNOPSIS

   use Munin::Common::Logger;

   DEBUG("verbose debug info");
   INFO("general operation info");
   NOTICE("significant expected event");
   WARN("unexpected but non-fatal");
   ERROR("something failed");
   CRITICAL("major failure");
   FATAL("unrecoverable, exiting");  # logs and dies
   ALERT("needs immediate attention");
   EMERGENCY("system unusable");

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

The functions DEBUG, INFO, NOTICE, WARN, ERROR, CRITICAL, FATAL, ALERT,
and EMERGENCY are exported by default.

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

Verbose debugging information. Only useful for developers debugging code.
Not logged in production (level defaults to 'warning').

    DEBUG "Entering subroutine foo with args: @args";

=item INFO

General information about normal operations. Startup messages, connection
status, configuration loaded.

    INFO "Starting munin-update for $host";
    INFO "Configuration reloaded";

=item NOTICE

Significant but expected events. New services discovered, state changes
that are normal.

    NOTICE "New service $plugin discovered on $host";

=item WARN

Something unexpected happened but the system continues. Degraded performance,
retrying a failed operation, missing optional config.

    WARN "Failed to connect to $host, retrying in 30s";
    WARN "Using default value for $config_key";

=item ERROR

Something failed but the system can continue. A single plugin failed,
one node unreachable, one graph could not be generated.

    ERROR "Plugin $plugin failed: $!";
    ERROR "Could not update $ds_name: $err";

=item CRITICAL

A major failure that affects functionality. Database connection lost,
cannot write to disk, multiple nodes unreachable.

    CRITICAL "Cannot open database: $DBI::errstr";

=item FATAL

Unrecoverable error. Logs at CRITICAL level and terminates the program.
Use when the process cannot continue at all.

    FATAL("Database connection failed: $!");  # logs and dies

=item ALERT

Requires immediate attention. Usually handled by monitoring systems.

    ALERT "Disk space critical on $host";

=item EMERGENCY

System is unusable. Entire monitoring system down.

    EMERGENCY "Munin master cannot start: $!";

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
