#
# Copyright (C) 2012 Diego Elio Pettenò
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
# perlpod.

=encoding utf8

=head1 NAME

Munin::Plugin::HTTP - LWP::UserAgent subclass for Munin plugins

=head1 SYNOPSIS

The Munin::Plugin::HTTP module extends L<LWP::UserAgent> with methods
useful for Munin plugins, as well as provide a more homogeneous
interface, as both exposed to the user and to the monitored services.

=head1 HTTP CONFIGURATION

HTTP plugins (that use this module) share a common configuration
interface, including some common system environment variables.

[plugin]
  env.http_timeout 25
  env.http_proxy http://mylocalproxy:3128/
  env.https_proxy http://mylocalproxy:3128/
  env.http_username someuser
  env.http_password somepassword

=over

=item C<env.http_timeout>

The timeout, in seconds, to use for HTTP requests. Default 25, to give
time for processing.

=item C<env.http_proxy>, C<env.https_proxy>

The proxy server to use when making the request. The plugins based on
this module will respect the system variables, as would tools like
wget and curl.

=item C<env.http_username>, C<env.http_password>

The username and password to use for authentication. This will only be
used if requested, for any realm that is requested. Basic auth is
supported.

Don't use this with HTTP proxies, put the passwords in the front of
the url in the form of C<http://user:pass@proxy/> instead.

=back

=head1 REQUIREMENTS

The module requires libwww-perl installed to work correctly.

=head1 AUTHOR

Diego Elio Pettenò <flameeyes@gentoo.org>

=cut

package Munin::Plugin::HTTP;

use strict;
use warnings;

use LWP::UserAgent;
use Munin::Plugin;

our (@ISA, $DEBUG);

@ISA = qw(LWP::UserAgent);

# Alias $Munin::Plugin::HTTP::DEBUG to $Munin::Plugin::DEBUG, so HTTP
# plugins don't need to import the latter module to get debug output.
*DEBUG = \$Munin::Plugin::DEBUG;

sub new {
  my $ua = LWP::UserAgent->new(timeout => ($ENV{'http_timeout'} || 25));

  $ua->agent(sprintf("munin/%s (%s; %s)",
		     $Munin::Common::Defaults::MUNIN_VERSION,
		     $Munin::Plugin::me,
		     $ua->_agent));

  $ua->env_proxy;

  return $ua;
}

sub get_basic_credentials {
  my ($realm, $uri, $isproxy) = $_;

  return $isproxy ? () : ($ENV{'http_username'}, $ENV{'http_password'});
}
