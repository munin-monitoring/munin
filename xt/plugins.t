
use strict;
use warnings;

use Test::More;
use File::Find ();
use Capture::Tiny ':all';

use v5.10.1;

use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;
my $num_plugins = 0;
my @plugins;

sub wanted {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid, $interpreter, $arguments );

    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
        && -f _
        && ( ( $interpreter, $arguments ) = hashbang("$_") )
        && ($interpreter)
        && ++$num_plugins
        && push @plugins, [ $name, $interpreter, $arguments ];
}

File::Find::find( { wanted => \&wanted }, 'plugins' );

plan tests => scalar(@plugins);


foreach my $plugin (@plugins) {
    process_file(@{$plugin});
}

sub hashbang {
    my ($filename) = @_;
    open my $file, '<', $filename;
    my $firstline = <$file>;
    close $file;

    $firstline =~ m{ ^\#!                    # hashbang
                     \s*                     # optional space
                     (?:/usr/bin/env\s+)?    # optional /usr/bin/env
                     (?<interpreter>\S+)     # interpreter
                     (?:\s+
                         (?<arguments>[^\n]*)   # optional interpreter arguments
                     )?
               }xms;

    return ( $+{interpreter}, $+{arguments} );
}

sub process_file {
    my ( $plugin, $interpreter, $arguments ) = @_;

    if ( $interpreter =~ m{/bin/sh} ) {
        subtest $plugin => sub {
            plan tests => 2;
            run_check(
                {   command     => [ 'sh', '-n', $plugin ],
                    description => 'sh syntax check'
                }
            );
            run_check(
                {   command     => [ 'checkbashisms', $plugin ],
                    description => 'checkbashisms'
                }
            );
        };
    }
    elsif ( $interpreter =~ m{/bin/ksh} ) {
        run_check(
            {   command     => [ 'ksh', '-n', $plugin ],
                description => 'ksh syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{bash} ) {
        run_check(
            {   command     => [ 'bash', '-n', $plugin ],
                description => 'bash syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{perl} ) {
        my $command;
        if ( $arguments =~ m{-.*T}mx ) {
            $command = [ 'perl', '-cwT', $plugin ];
        }
        else {
            $command = [ 'perl', '-cw', $plugin ];
        }
        run_check(
            {   command     => $command,
                description => 'perl syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{python} ) {
        run_check(
            {   command     => [ 'python3', '-m', 'py_compile', $plugin ],
                description => 'python compile',
                filename    => $plugin
            }
        );

        # Clean up after python
        my $compiled_file = $plugin . "c";
        unlink $compiled_file;
    }
    elsif ( $interpreter =~ m{php} ) {
        run_check(
            {   command     => [ 'php', '-l', $plugin ],
                description => 'php syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{j?ruby} ) {
        run_check(
            {   command     => [ 'ruby', '-cw', $plugin ],
                description => 'ruby syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{gawk} ) {
        run_check(
            {   command => [
                    'gawk', '--source', 'BEGIN { exit(0) } END { exit(0) }',
                    '--file', $plugin
                ],
                description => 'gawk syntax check',
                filename    => $plugin
            }
        );
    }
    elsif ( $interpreter =~ m{expect} ) {
    SKIP: {
            skip 'no idea how to check expect scripts', 1;
            pass("No pretending everything is ok");
        }
    }
    else {
        fail( $plugin . " unknown interpreter " . $interpreter );
    }
}

sub run_check {
    my ($args)        = @_;
    my $check_command = $args->{command};
    my $description   = $args->{description};
    my $filename      = $args->{filename};

    my $message;

    if ($filename) {
        $message = sprintf( '%s: %s', $filename, $description );
    }
    else {
        $message = $description;
    }

    my ( $stdout, $stderr, $exit ) = capture {
        system( @{$check_command} );
    };

    ok( ( $exit == 0 ), $message );

    if ($exit) {
        diag(
            sprintf(
                "\nCommand: %s\n\nSTDOUT:\n\n%s\n\nSTDERR:\n\n%s\n\n",
                join( " ", @{$check_command} ),
                $stdout, $stderr
            )
        );
    }
}
