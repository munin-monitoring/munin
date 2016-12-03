#!/usr/bin/perl
# -*- cperl -*-
#
# Copyright (C) 2013 Gilles Fauvie, OPENDBTEAM.com (INTEGER S.P.R.L)
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

=head1 NAME

postgres_tuplesratio_ - Plugin to monitor PostgreSQL live/dead tuples ratio.

=head1 CONFIGURATION

Configuration is done through libpq environment variables, for example
PGUSER, PGDATABASE, etc. For more information, see L<Munin::Plugin::Pgsql>.

To monitor a specific database, link to postgres_tuplesratio_<databasename>.
To monitor all databases, link to postgres_tuplesratio_ALL.

=head1 SEE ALSO

L<Munin::Plugin::Pgsql>

=head1 MAGIC MARKERS

 #%# family=auto
 #%# capabilities=autoconf suggest

=head1 AUTHOR

Gilles Fauvie <gfauvie@opendbteam.com>, OPENDBTEAM.com (INTEGER S.P.R.L)

=head1 COPYRIGHT/License.

Copyright (c) 2013 Gilles Fauvie, OPENDBTEAM.com (INTEGER S.P.R.L)

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the terms of the GNU General
Public License as published by the Free Software Foundation; version 2
dated June, 1991.

=cut

use warnings;
use strict;

use Munin::Plugin::Pgsql;

my $pg = Munin::Plugin::Pgsql->new(
    basename => 'postgres_tuplesratio_',
    title    => 'PostgreSQL tuples ratio',
    info     => 'Ratio dead/live tuples of a database',
    vlabel   => 'Nbr',
    paramdatabase => 1,
    pivotquery => 1,
    basequery =>
	"select sum(n_live_tup) as livetup, sum(n_dead_tup) as deadtup from pg_stat_user_tables",
    configquery    => "values('livetup', 'livetup'), ('deadtup', 'deadtup')",
    suggestquery =>
        "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate AND NOT datname='postgres' UNION ALL SELECT 'ALL' ORDER BY 1 LIMIT 10",
    graphdraw => 'AREA',
    stack     => 1
);

$pg->Process();
exit(0);