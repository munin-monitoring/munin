# -*- cperl -*-
#
# Copyright (C) 2009 Magnus Hagander, Redpill Linpro AB
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 2 dated June,
# 1991.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA.

# This Module is user documented inline, interspersed with code with
# perlpod.  The documentation for the session() function is the
# pattern.  Please maintain it in the same way.


# $Id$

=head1 NAME

Munin::Plugin::Pgsql - Base module for PostgreSQL plugins for Munin

=head1 SYNOPSIS

The Munin::Plugin::Pgsql module provides base functionality for all
PostgreSQL Munin plugins.

=head1 CONFIGURATION

To Be Done

=head1 More documentation needed

There is more documentation here that needs to be written

=head1 TODO

Lots.

=head1 BUGS

I'm sure there are plenty.

=head1 SEE ALSO

L<DBD::Pg>

=head1 AUTHOR

Magnus Hagander

=head1 COPYRIGHT/License.

Copyright (c) 2009 Magnus Hagander.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
dated June, 1991.

=cut

package Munin::Plugin::Pgsql;

use strict;
use warnings;

use DBI;

sub new {
    my ($class) = shift;
    my (%args)  = @_;

    my %defaults = (
        base      => 1000,
        graphdraw => 'LINE1',
        graphtype => 'GAUGE'
    );

    my $self = {
        debug          => 0,
        basename       => $args{basename},
        basequery      => $args{basequery},
        title          => $args{title},
        info           => $args{info},
        vlabel         => $args{vlabel},
        graphdraw      => $args{graphdraw},
        graphtype      => $args{graphtype},
        stack          => $args{stack},
        configquery    => $args{configquery},
        base           => $args{base},
        wildcardfilter => $args{wildcardfilter},
        suggestquery   => $args{suggestquery},
    };

    foreach my $k (keys %defaults) {
        unless (defined $self->{$k}) {
            $self->{$k} = $defaults{$k};
        }
    }
    return bless $self, $class;
}

sub Config {
    my ($self) = @_;
    print "graph_title $self->{title}\n";
    print "graph_vlabel $self->{vlabel}\n";
    print "graph_category PostgreSQL\n";
    print "graph_info $self->{info}\n";
    print "graph_args --base $self->{base}\n";

    my %rowinfo = ();
    if ($self->{configquery}) {
        my $r = $self->runquery($self->{configquery});
        foreach my $row (@$r) {
            $rowinfo{$row->[0]} = 1;
        }
    }

    my $firstrow = 1;
    foreach my $row (@{$self->runquery($self->{configquery})}) {
        my $l = $row->[0];
        print "$l.label $row->[1]\n";
        print "$l.info $row->[2]\n" if (defined $row->[2]);
        print "$l.type $self->{graphtype}\n";
        if ($self->{stack} && !$firstrow) {
            print "$l.draw STACK\n";
        }
        else {
            print "$l.draw $self->{graphdraw}\n";
        }
        $firstrow = 0;
    }
}

sub Autoconf {
    my ($self) = @_;

    if (!$self->connect(1)) {
        print "no ($self->{connecterror})\n";
        return 1;
    }

    # More magic needed?
    print "yes\n";
    return 0;
}

sub Suggest {
    my ($self) = @_;

    if ($self->{suggestquery}) {
        my $r = $self->runquery($self->{suggestquery});
        foreach my $row (@$r) {
            print $row->[0] . "\n";
        }
        return 0;
    }
    die "Plugin can't do suggest, why did you try?\n";
}

sub GetData {
    my ($self) = @_;
    if ($self->{basequery}) {
        my $q = $self->{basequery};
        my $w = $self->wildcard_parameter();
        my @p = ();
        if ($w) {
            while ($q =~ s/%%FILTER%%/$self->{wildcardfilter}/) {
                push @p, $self->wildcard_parameter();
            }
        }
        else {

            # Not called as a wildcard, or called with "all" - remove filter spec
            $q =~ s/%%FILTER%%//g;
        }
        my $r = $self->runquery($q, @p);
        foreach my $row (@$r) {
            my $l = $row->[0];
            print $row->[0] . ".value " . $row->[1] . "\n";
        }
        return;
    }
    die "No query configured!";
}

sub Process {
    my ($self) = @_;

    if (defined $ARGV[0] && $ARGV[0] ne '') {
        if ($ARGV[0] eq 'autoconf') {
            return $self->Autoconf();
        }
        elsif ($ARGV[0] eq 'debug') {
            $self->debug = 1;
        }
        elsif ($ARGV[0] eq 'config') {
            return $self->Config();
        }
        elsif ($ARGV[0] eq 'suggest') {
            return $self->Suggest();
        }
        else {
            print "Unknown command: '$ARGV[0]'\n";
            return 1;
        }
    }

    return $self->GetData();
}

# Internal useful functions
sub connect() {
    my ($self, $noexit) = @_;

    my $r = $self->_connect();
    return 1 if ($r);         # connect successful
    return 0 if ($noexit);    # indicate failure but don't exit
    print "Failed to connect to database: $self->{connecterror}\n";
    exit(1);
}

sub _connect() {
    my ($self, $noexit) = @_;

    return 1 if ($self->{dbh});

    if (eval "require DBD::Pg;") {

        #FIXME: Don't hardcode
        $self->{dbh} = DBI->connect('DBI:Pg:dbname=postgres;host=/tmp');
        unless ($self->{dbh}) {
            $self->{connecterror} = "$DBI::errstr";
            return 0;
        }
    }
    else {
        if ($noexit) {
            $self->{connecterror} = "DBD::Pg not found, and cannot do psql yet";
            return 0;
        }
    }
    return 1;
}

sub runquery {
    my ($self, $query, @params) = @_;
    $self->connect();
    if ($self->{dbh}) {

        # Run query on DBI
        my $s = $self->{dbh}->prepare($query);
        my $r = $s->execute(@params);
        unless ($r) {
            print "Query failed!\n";
            exit(1);
        }
        return $s->fetchall_arrayref();
    }
    print "AIIEH\n";
    exit(1);
}

sub wildcard_parameter {
    my ($self) = @_;

    return undef unless (defined $self->{basename});

    if ($0 =~ /$self->{basename}(.*)$/) {
        return undef if ($1 eq "all");
        return $1;
    }
    die "Wildcard base not found in called filename!\n";
}

1;
