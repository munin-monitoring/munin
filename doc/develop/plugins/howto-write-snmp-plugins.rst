.. _howto-write-snmp-plugins:

=========================
How to write SNMP Plugins
=========================

This HOWTO is not quite done yet.

As writing a Munin plugin is simple writing a SNMP one is even simpler. The
SNMP agent on the device has done all the hard work for us. We just need to be
able to autodetect if a particular device supports our plugin, and then present
the stats the SNMP agent gives us.

If you do not know or understand what SNMP is or what a community string is
used for please find (and read) some general SNMP material before you go on.

Supporting library
------------------

If you have used SNMP plugins with Munin you may have noticed that there is a
uniform way to configure them. This is implemented in the perl library
`Munin::Plugin::SNMP` (Perl module) which is supplied in Munin 1.4.

If you run `perldoc Munin::Plugin::SNMP` you'll see the programmers
documentation for the module and its public functions - as usual. This also
explains how to configure a plugin using this module for different
authentications and versions of SNMP.

A load plugin
-------------

Returning to the absolute simplest case I would have picked a `snmp__load`
plugin for this HOWTO, but not many devices supports that. Uptime on the other
hand is very basic to SNMP devices. If you snmpwalk some device the uptime will
be there among the first 10 lines:

::

        DISMAN-EVENT-MIB::sysUpTimeInstance = Timeticks: (138007908) 15 days, 23:21:19.08

The numeric OID for that is

::

        $ snmptranslate -On DISMAN-EVENT-MIB::sysUpTimeInstance
        .1.3.6.1.2.1.1.3.0

A Perl script to get the basics

::

        #! /usr/bin/perl

        use strict;
        use warnings;
        use Munin::Plugin::SNMP;

        my $session = Munin::Plugin::SNMP->session(-translate =>
                                                   [ -timeticks => 0x0 ]);

        my $uptime = $session->get_single (".1.3.6.1.2.1.1.3.0") || 'U';

        if ($uptime ne 'U') {
            $uptime /= 8640000; # Convert to days
        }

        print "uptime.value ", $uptime, "\n";

The `-translate` option is to stop the SNMP stack from converting the timetics
into a human readable time string, we want a integer to graph.

If you call this `snmp__uptime` and then in `/etc/munin/plugins` make a symlink
to it: If your device is called "switch" (this should be in DNS (or the hosts
file) and possible to look up): `ln -s snmp_switch_uptime ...`

Then the plugin has to be configured, `/etc/munin/plugin-conf.d/snmp` for the imagined device called "switch":

::

        [snmp_*]
           env.version 2
           env.community public

Now you can do munin-run snmp_switch_uptime as root:

::

        # munin-run snmp_switch_uptime
        uptime.value 15.979475462963

You need a config section too.

::

        if (defined $ARGV[0] and $ARGV[0] eq "config") {
            my ($host) = Munin::Plugin::SNMP->config_session();
                print "host_name $host\n" unless $host eq 'localhost';
                print "graph_title System Uptime
        graph_args --base 1000 -l 0
        graph_vlabel uptime in days
        graph_category system
        graph_info This graph shows the number of days that the the host is up and running so far.
        uptime.label uptime
        uptime.info The system uptime itself in days.
        uptime.draw AREA
        ";
                exit 0;
        }

That makes the plugin configurable. Please notice that the plugin prints a
`host_name` line if it's not examining the locahost. This is the way Munin
knows which device a non-local plugin is examining.

All cool and good. Now we need it to autoconfigure for each new SNMP agent you
configure for. In general you would run this command:

::

        # munin-node-configure --snmp --snmpversion 2 --snmpcommunity public 192.168.2.0/24 | sh -x

This will interogate all IP addresses in the given CIDR range with the given
SNMP version and community string and then the script figures out which SNMP
plugins will work on a device it finds and makes goes ln -s snmp_switch_uptime
`/usr/share/munin/plugins/snmp__uptime` if the device known as "switch" supports
the uptime plugin.

The way it does this is by knowing which plugins to talk to, and then by asking
them what OIDs they are interested in:

::

        =head1 MAGIC MARKERS

          #%# family=snmpauto
          #%# capabilities=snmpconf

        ...

        =cut

        ...

        if (defined $ARGV[0] and $ARGV[0] eq "snmpconf") {
                print "require 1.3.6.1.2.1.1.3.0 [0-9]\n"; # Number
                exit 0;
        }

Given those magic markers munin-node-configure will run the plugin with the
argument snmpconf which makes the plugin tell munin-node-configure what OIDs it
requires for operation.

In a more complex case, `snmp__if_` more is needed to generate the needed
symlinks:

::

        # TODO
