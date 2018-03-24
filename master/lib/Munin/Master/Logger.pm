package Munin::Master::Logger;

# $Id$

=encoding utf-8

=head1 NAME

Munin::Master::Logger - Munin master's old logging routines

=head1 SYNOPSIS

This module contains Munin master's old logging routines while we're
switching to Log::Log4perl.  It also sets up Log4perl according to our
needs.

Do not use "logger" when writing new code, use the
Log::Log4perl :easy API.  This module takes care of initializing
Log::Log4perl at load time.

=head1 SUBROUTINES

=over

=item B<logger_open>

needs to be called once in the main program with one argument: The
directory where the munin logs goes.  The running programs name ($0)
will be used as the log name (e.g. munin-graph.log).

=item B<logger>

Do not use.

=item B<logger_level>

Use to set the programs log level to debug, info, warn, error,
or fatal.  This corresponds to the log levels used in syslog, but
syslog is not used for logging.

=item B<logger_debug>

Set up DEBUG logging.  Both STDOUT and the log file will receive DEBUG
level output.

=back

=head1 AUTHOR

Munin master logging ported to Log4perl by Nicolai Langfeldt.  Split
out into this module by Kjell Magne Øierud.

=head1 LICENSE

GPLv2

=cut

use base qw(Exporter);

use strict;
use warnings;

use Carp qw(confess);
use English qw(-no_match_vars);
use File::Basename qw(basename);
use Log::Log4perl qw(:easy);

our @EXPORT = qw(logger_open logger_open_stderr logger_debug logger_level logger);

# Early open of the log.  Warning and more urgent messages will go to
# screen.

Log::Log4perl->easy_init( $WARN );

my $logdir = undef;
my $logopened = 0;
my $me = $1 if basename($PROGRAM_NAME) =~ m/(.*)/; # Fast untaint $PROGRAM_NAME

sub _warn_catcher {
    if ($logopened) {
	WARN "[PERL WARNING] ".join(" ",@_);
    } else {
	print STDERR join(" ",@_);
    }
}

sub logger_open_stderr {
    if (!$logopened) {
	# I'm a bit uncertain about the :utf8 bit.
	Log::Log4perl->easy_init( { level    => $INFO,
				    file     => ":utf8>&STDERR" } );
	$logopened = 1;
    }

    get_logger('')->debug("Opened log file");

    # Get perl warnings into the log files
    $SIG{__WARN__} = \&_warn_catcher;

}

sub logger_open {
    # This is called when we have a directory and file name to log in.

    my $dirname = shift;
    $logdir=$dirname;

    if (!defined($dirname)) {
	confess("In logger_open, directory for log files undefined");
    }

    my $log_filename = shift || "$dirname/$me.log";

    if (!$logopened) {
	# I'm a bit uncertain about the :utf8 bit.
	Log::Log4perl->easy_init( { level    => $INFO,
				    file     => ":utf8>>$log_filename" } );
	# warn "Logging to $dirname/$me.log";
	$logopened = 1;
    }

    get_logger('')->debug("Opened log file");

    # Get perl warnings into the log files
    $SIG{__WARN__} = \&_warn_catcher;
}

sub logger_debug {
    # Adjust log level to DEBUG if user gave --debug option
    my $logger = get_logger('');

    WARN "Setting log level to DEBUG\n";

    if (defined($logdir)) {
	Log::Log4perl->easy_init( { level    => $DEBUG,
				    file     => ":utf8>>$logdir/$me.log" },
				  { level    => $DEBUG,
				    file     => "STDERR" } );
    } else {
	# If we do not have a log file name to log to just send
	# everything to STDERR
	Log::Log4perl->easy_init( { level    => $DEBUG,
				    file     => "STDERR" } );
    }
    # And do not open the loggers again now.
    $logopened=1;
}

sub logger_level {
    my ($loglevel) = @_;

    my $logger = get_logger('');

    $loglevel = lc $loglevel;
    my %level_map = (
        debug => $DEBUG,
        info  => $INFO,
        warn  => $WARN,
        error => $ERROR,
        fatal => $FATAL,
    );

    unless ($level_map{$loglevel}) {
        ERROR "Unknown log level: '$loglevel'\n";
        return;
    }

    $logger->level($level_map{$loglevel});

    INFO "Setting log level to $loglevel\n";
}

sub logger {
  my ($comment) = @_;

  INFO @_;
}

1;
