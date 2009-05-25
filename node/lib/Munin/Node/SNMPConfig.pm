package Munin::Node::SNMPConfig;

use strict;
use warnings;

use Net::SNMP;
use Socket;

use Munin::Common::Defaults;
use Munin::Node::Config;

use Exporter ();
our @ISA = qw/Exporter/;
our @EXPORT = qw//;


my $config = Munin::Node::Config->instance();

my $sysName      = "1.3.6.1.2.1.1.5.0";
my $name;

my $session;
my $error;
my $response;

my @plugins;

my %plugconf;
my %hostconf;

foreach my $plugin (@plugins)
{
	&fetch_plugin_config ($plugin, \%plugconf);
}

while (my $addr = shift)
{
	my $num = 32;
	if ($addr =~ /([^\/]+)\/(\d+)/)
	{   
		$num  = $2;
		$addr = $1;
	}   
	$num = 32 - $num;
	$num = 2 ** $num;
	print "# Doing $addr / $num\n" if $config->{DEBUG};
	for (my $i = 0; $i < $num; $i++)
	{
		print "# Doing $addr -> $i...\n" if $config->{DEBUG};
		my $tmpaddr = $addr;
		if ($tmpaddr =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/)
		{
			my @tmpaddr = split (/\./, $tmpaddr);
			$tmpaddr[3] += $i;
			$tmpaddr = gethostbyaddr (inet_aton (join ('.', @tmpaddr)), AF_INET);
			$tmpaddr ||= join ('.', @tmpaddr);
		}
		print "# ($tmpaddr)\n" if $config->{DEBUG};
		&do_host ("$tmpaddr", $config->{snmp_community}, $config->{snmp_version}, $config->{snmp_port});
	}
}


#interfaces ($name);

sub do_host
{
	my $host = shift;
	my $comm = shift;
	my $ver  = shift;
	my $port = shift;

	if ($host =~ /([^:]+):(\d+)/)
	{
		$host = $1;
		$port = $2;
	}

	($session, $error) = Net::SNMP->session(
			-hostname  => $host,
			-community => $comm,
			-port      => $port,
			-version   => $ver,
		);
	$session->translate (0);
	die $error if $error;

	if (!defined ($session))
	{
		print "# Dropping host \"$host\": $error" . "\n";
		return 0;
	}

	if (!defined ($response = $session->get_request($sysName)))
	{
		print "# Dropping host \"$host\": " . $session->error() . "\n";
		return 0;
	}
	$name = $response->{$sysName};

	foreach my $plugin (@plugins)
	{
		my $auto = snmp_autoconf_plugin ($plugin, \%plugconf, \%hostconf, $host);

		if (defined $auto)
		{
			if ($plugconf{$plugin}->{wild})
			{
				foreach my $id (@{$auto})
				{
					if (! -e "$config->{servicedir}/snmp_$host"."_$plugin"."_$id")
					{
						print "ln -s $config->{libdir}/snmp__$plugin", "_ $config->{servicedir}/snmp_$host", "_$plugin", "_$id\n";
					}
				}
			}
			else
			{
				if (! -e "$config->{servicedir}/snmp_$host"."_$plugin")
				{
					print "ln -s $config->{libdir}/snmp__$plugin", " $config->{servicedir}/snmp_$host", "_$plugin\n";
				}
			}
		}
	}
}

sub snmp_autoconf_plugin
{
	my $plugname = shift;
	my $plugconf = shift;
	my $hostconf = shift;
	my $host     = shift;

	print "# Running autoconf on $plugname for $host...\n" if $config->{DEBUG};

    # First round of requirements
	if (defined $plugconf->{$plugname}->{req})
	{
		print "# Checking requirements...\n" if $config->{DEBUG};
		foreach my $req (@{$plugconf->{$plugname}->{req}})
		{
			if ($req->[0] =~ /\.$/)
			{
				print "# Delaying testing of $req->[0], as we need the indexes first.\n" if $config->{DEBUG};
				next;
			}
			my $snmp_val = snmp_get_single ($session, $req->[0]);
			if (!defined $snmp_val or $snmp_val !~ /$req->[1]/)
			{
				print "# Nope. Duh.\n" if $config->{DEBUG};
				return;
			}
		}
	}

    # We need the number of "things" to autoconf

	my $num = 1;
	if (defined $plugconf->{$plugname}->{num})
	{
		$num = snmp_get_single ($session, $plugconf->{$plugname}->{num});
		return if !defined $num;
	}
	print "# Number of items to autoconf is $num...\n" if $config->{DEBUG};

    # Then the index base
	my $indexes;
	if (defined $plugconf->{$plugname}->{ind})
	{
		$indexes = snmp_get_index ($plugconf->{$plugname}->{ind}, $num);
		return if !defined $indexes;
	}
	else
	{
		$indexes->{0} = 1;
	}
	print "# Got indexes: ", join (',', keys (%{$indexes})), "\n" if $config->{DEBUG};

	return unless scalar keys %{$indexes};

    # Second round of requirements (now that we have the indexes)
	if (defined $plugconf->{$plugname}->{req})
	{
		print "# Checking requirements...\n" if $config->{DEBUG};
		foreach my $req (@{$plugconf->{$plugname}->{req}})
		{
			if ($req->[0] !~ /\.$/)
			{
				print "# Already tested of $req->[0], before we got hold of the indexes.\n" if $config->{DEBUG};
				next;
			}
			
			foreach my $key (keys %$indexes)
			{
				my $snmp_val = snmp_get_single ($session, $req->[0] . $key);
				if (!defined $snmp_val or $snmp_val !~ /$req->[1]/)
				{
					print "# Nope. Deleting $key from possible solutions.\n" if $config->{DEBUG};
					delete $indexes->{$key}; # Disable
				}
			}
		}
	}

	my @tmparr = sort keys %$indexes;
	return \@tmparr;
}

sub snmp_get_single
{
	my $session = shift;
	my $oid     = shift;

	if ((!defined ($response = $session->get_request($oid))) or
			$session->error_status)
	{
		return;
	}
	print "# Fetched value \"$response->{$oid}\"\n" if $config->{DEBUG}; 
	return $response->{$oid};
}

sub snmp_get_index
{
	my $oid   = shift;
	my $num   = shift;
	my $ret   = $oid . "0";
	my $rhash = {};

	$num++; # Avaya switch b0rkenness...

	for (my $i = 0; $i < $num; $i++)
	{
		if ($i == 0)
		{
			print "# Checking for $ret\n" if $config->{DEBUG};
			$response = $session->get_request($ret);
		}
		if ($i or !defined $response or $session->error_status)
		{
			print "# Checking for sibling of $ret\n" if $config->{DEBUG};
			$response = $session->get_next_request($ret);
		}
		if (!$response or $session->error_status)
		{
			return;
		}
		my @keys = keys %$response;
		$ret = $keys[0];
		last unless ($ret =~ /^$oid\d+$/);
		print "# Index $i: ", join ('|', @keys), "\n" if $config->{DEBUG};
		$rhash->{$response->{$ret}} = 1;
	}
	return $rhash;
}

sub interfaces
{
	my $name = shift;
	my %interfaces = ();
	my $num;
	my $ifNumber     = "1.3.6.1.2.1.2.1.0";
	my $ifEntryIndex = "1.3.6.1.2.1.2.2.1.1"; # dot something
	my $ifEntryType  = "1.3.6.1.2.1.2.2.1.3"; # dot something
	my $ifEntrySpeed = "1.3.6.1.2.1.2.2.1.5"; # dot something

	print "# System name: ", $name, "\n" if $config->{DEBUG};

	if (!defined ($response = $session->get_request($ifNumber)) or 
			$session->error_status)
	{
		die "Croaking: " . $session->error();
	}

	$num = $response->{$ifNumber} +1; # Add one because of bogus switch entries
	print "# Number of interfaces: ", $num, "\n" if $config->{DEBUG};

	my $ret = $ifEntryIndex . ".0";

	for (my $i = 0; $i < $num;)
	{
		if ($i == 0)
		{
			$response = $session->get_request($ret);
		}
		if ($i or !defined $response or $session->error_status)
		{
			$response = $session->get_next_request($ret);
		}
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		$ret = $keys[0];
		last unless ($ret =~ /^$ifEntryIndex\.\d+$/);
		print "# Index $i: ", join ('|', @keys), "\n" if $config->{DEBUG};
		$interfaces{$response->{$ret}} = 1;
		$i++;
	}

	foreach my $key (keys %interfaces)
	{
		$response = $session->get_request($ifEntrySpeed . "." . $key);
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		print "# Speed $key: ", join ('|', @keys), ": ", $response->{$keys[0]}, "\n" if $config->{DEBUG};
		if ($response->{$keys[0]} == 0)
		{
			delete $interfaces{$key};
		}
	}

	foreach my $key (keys %interfaces)
	{
		$response = $session->get_request($ifEntryType . "." . $key);
		if (!$response or $session->error_status)
		{
			die "Croaking: ", $session->error();
		}
		my @keys = keys %$response;
		print "# Type  $key: ", join ('|', @keys), ": ", $response->{$keys[0]}, "\n" if $config->{DEBUG};
		if ($response->{$keys[0]} != 6)
		{
			delete $interfaces{$key};
		}
	}

	foreach my $key (sort keys %interfaces)
	{
		print "snmp_${name}_if_$key\n";
	}
}



#
#		if (defined $p->{'capability'}->{'snmpconf'})
#		{
#			$plug =~ s/^snmp__//;
#			$plug =~ s/_$//;
#			push (@plugins, $plug);
#		}

1;

__END__


=head1 NAME

munin-node-configure-snmp - A sub-program used by munin-node-configure to
do the actual SNMP probing.

=head1 SYNOPSIS

munin-node-configure-snmp [options] <host/cidr> [host/cidr] [...]

=head1 DESCRIPTION

Munin's node is a daemon that Munin connects to fetch data. This data is
stored in .rrd-files, and later graphed and htmlified. It's designed to
let it be very easy to graph new datasources.

Munin-node-configure-snmp is a program that is used by another program in
the Munin package, munin-node-configure, to do SNMP probing of hosts or
networks.

This program is only meant to be run by other programs in the Munin
package, not by hand.

=head1 VERSION

This is munin-node v@@VERSION@@

=head1 AUTHORS

Jimmy Olsen.

=head1 BUGS

munin-node-configure-snmp does not have any known bugs.

Please report other bugs in the bug tracker at L<http://munin.sf.net/>.

=head1 COPYRIGHT

Copyright © 2004 Jimmy Olsen.

This is free software; see the source for copying conditions. There is
NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.

This program is released under the GNU General Public License

=cut

