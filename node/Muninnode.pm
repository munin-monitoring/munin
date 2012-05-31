package Muninnode;
# Copyright (C) 2004-2006 Audun Ytterdal, Jimmy Olsen, Nicolai Langfeldt
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# $Id: munin-node.in 1026 2006-06-14 20:13:14Z janl $

use Exporter;
@ISA = ('Exporter');
@EXPORT=();

use strict;

my $VERSION = '@@VERSION@@';
my $CONFDIR = '@@CONFDIR@@';
my $PLUGINUSER = '@@PLUGINUSER@@';
my $GROUP = '@@GROUP@@';
my $STATEDIR = '@@STATEDIR@@';
my $PLUGSTATE = '@@PLUGSTATE@@';
