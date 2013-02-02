package Munin::Common::Logger;
use base qw(Log::Dispatch);

use strict;
use warnings;
use Munin::Common::Defaults;
use POSIX qw(strftime);

# Todo: Move to config
my $use_syslog = 1;
my $use_screen = 1;
my $use_file   = 0;

sub new {
    my ( $class, $args ) = @_;

    my $self = $class->SUPER::new();

    $self->{identity} = $args->{identity} ||= '';

    $self->{config}->{debug} = $args->{config}->{debug};

    $self->{config}->{logdir} = $args->{config}->{logdir}
        ||= $Munin::Common::Defaults::MUNIN_LOGDIR;

    if ($use_file) {
        $self->_add_file;
    }

    if ($use_screen) {
        $self->_add_screen;
    }

    if ($use_syslog) {
        $self->_add_syslog;
    }

    return $self;
}

sub _add_file {
    my $self = shift;
    use Log::Dispatch::File;

    my $logfile = sprintf( "%s/munin-%s.log",
        $self->{config}->{logdir},
        $self->{identity} );

    my $min_level = $self->{config}->{debug} ? 'debug' : 'warning';

    # my $min_level = 'debug';

    my $file_format = sub {
        my %args    = @_;
        my $message = sprintf( "%s [%s] %s\n",
            $self->_timestamp, uc $args{level},
            $args{message} );
        return $message;
    };

    $self->add(
        Log::Dispatch::File->new(
            name      => 'file',
            min_level => $min_level,
            filename  => $logfile,
            callbacks => $file_format,
        )
    );
}

sub _add_screen {
    my $self = shift;
    use Log::Dispatch::Screen;

    my $screen_format = sub {
        my %args = @_;
        return sprintf(
            "%s [%s] %s: %s\n",
            $self->_timestamp, uc $args{level},
            $self->{identity}, $args{message}
        );
    };

    $self->add(
        Log::Dispatch::Screen->new(
            name      => 'screen',
            min_level => 'warning',
            callbacks => $screen_format
        )
    );
}

sub _add_syslog {
    my $self = shift;
    use Log::Dispatch::Syslog;

    my $syslog_ident
        = $self->{identity}
        ? sprintf( 'munin/%s', $self->{identity} )
        : 'munin';

    $self->add(
        Log::Dispatch::Syslog->new(
            name      => 'syslog',
            min_level => 'debug',
            ident     => $syslog_ident
        )
    );
}

sub _timestamp { return strftime( "%Y-%m-%d %H:%M:%S", localtime ) }

1;
