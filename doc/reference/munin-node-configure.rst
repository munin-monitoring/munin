.. _munin-node-configure:


======================
 munin-node-configure
======================

SYNOPSIS
========

munin-node-configure [options]

DESCRIPTION
===========

munin-node-configure reports which plugins are enabled on the current node, and suggest changes to
this list.

By default this program shows which plugins are activated on the system.

If you specify "--suggest", it will present a table of plugins that will probably work (according to
the plugins' autoconf command).

If you specify "--snmp", followed by a list of hosts, it will present a table of SNMP plugins that
they support.

If you additionally specify "--shell", shell commands to install those same plugins will be printed.
These can be reviewed or piped directly into a shell to install the plugins.

OPTIONS
=======

General options
---------------

.. option:: --help

   Show this help page.

.. option:: --version

   Show version information.

.. option:: --debug

   Print debug information on the operations of "munin-node-configure". This can be very verbose.

   All debugging output is printed to STDOUT, and each line is prefixed with '#'. Only errors are
   printed to STDERR.

.. option:: --pidebug

   Plugin debug. Sets the environment variable MUNIN_DEBUG to 1 so that plugins may enable
   debugging.

.. option:: --config <file>

   Override configuration file [/etc/munin/munin-node.conf]

.. option:: --servicedir <dir>

   Override plugin directory [/etc/munin/plugins/]

.. option:: --sconfdir <dir>

   Override plugin configuration directory [/etc/munin/plugin-conf.d/]

.. option:: --libdir <dir>

   Override plugin library [/usr/share/munin/plugins/]

.. option:: --exitnoterror

   Do not consider plugins that exit non-zero exit-value as error.

.. option:: --suggest

   Suggest plugins that might be added or removed, instead of those that are currently enabled.

Output options
--------------

By default, "munin-node-configure" will print out a table summarising the results.

.. option:: --shell

   Instead of a table, print shell commands to install the new plugin suggestions.

   This implies "--suggest", unless "--snmp" was also enabled. By default, it will not attempt to
   remove any plugins.

.. option:: --remove-also

   When "--shell" is enabled, also provide commands to remove plugins that are no longer applicable
   from the service directory.

Plugin selection options
------------------------

.. option:: --families <family,...>

   Override the list of families that will be used (auto, manual, contrib, snmpauto). Multiple
   families can be specified as a comma-separated list, by repeating the "--families" option, or as
   a combination of the two.

   When listing installed plugins, the default families are 'auto', 'manual' and 'contrib'. Only
   'auto' plugins are checked for suggestions. SNMP probing is only performed on 'snmpauto' plugins.

.. option:: --newer <version>

   Only consider plugins added to the Munin core since <version>. This option is useful when
   upgrading, since it can prevent plugins that have been manually removed from being reinstalled.
   This only applies to plugins in the 'auto' family.

SNMP options
------------

.. option:: --snmp <host|cidr,...>

   Probe the SNMP agents on the host or CIDR network (e.g. "192.168.1.0/24"), to see what plugins
   they support. This may take some time, especially if the many hosts are specified.

   This option can be specified multiple times, or as a comma-separated list, to include more than
   one host/CIDR.

.. option:: --snmpversion <ver>

   The SNMP version (1, 2c or 3) to use. ['2c']

.. option:: --snmpport <port>

   The SNMP port to use [161]

.. option:: --snmpdomain <domain>

   The Transport Domain to use for exchanging SNMP messages. The default
   is UDP/IPv4. Possible values: 'udp', 'udp4', 'udp/ipv4'; 'udp6',
   'udp/ipv6'; 'tcp', 'tcp4', 'tcp/ipv4'; 'tcp6', 'tcp/ipv6'.

SNMP 1/2c authentication
~~~~~~~~~~~~~~~~~~~~~~~~

SNMP versions 1 and 2c use a "community string" for authentication. This is a shared password, sent
in plaintext over the network.

.. option:: --snmpcommunity <string>

The community string for version 1 and 2c agents. ['public'] (If this works your device is probably
very insecure and needs a security checkup).

SNMP 3 authentication
~~~~~~~~~~~~~~~~~~~~~

SNMP v3 has three security levels. Lowest is "noAuthNoPriv", which provides neither authentication
nor encryption. If a username and "authpassword" are given it goes up to "authNoPriv", and the
connection is authenticated. If "privpassword" is also given the security level becomes "authPriv",
and the connection is authenticated and encrypted.

Note: Encryption can slow down slow or heavily loaded network devices. For most uses "authNoPriv"
will be secure enough -- the password is sent over the network encrypted in any case.

ContextEngineIDs are not (yet) supported.

For further reading on SNMP v3 security models please consult RFC3414 and the documentation for Net::SNMP.

.. option:: --snmpusername <name>

   Username.  There is no default.

.. option:: --snmpauthpass <password>

   Authentication password. Optional when encryption is also enabled, in which case defaults to the
   privacy password ("--snmpprivpass").

.. option:: --snmpauthproto <protocol>

   Authentication protocol. One of 'md5' or 'sha' (HMAC-MD5-96, RFC1321 and SHA-1/HMAC-SHA-96, NIST
   FIPS PIB 180, RFC2264). ['md5']

.. option:: --snmpprivpass <password>

   Privacy password to enable encryption. There is no default. An empty ('') password is considered
   as no password and will not enable encryption.

   Privacy requires a privprotocol as well as an authprotocol and a authpassword, but all of these
   are defaulted (to 'des', 'md5', and the privpassword value, respectively) and may therefore be
   left unspecified.

.. option:: --snmpprivproto <protocol>

   If the privpassword is set this setting controls what kind of encryption is used to achieve
   privacy in the session. Only the very weak 'des' encryption method is supported officially.
   ['des']

   munin-node-configure also supports '3des' (CBC-3DES-EDE, aka Triple-DES, NIST FIPS 46-3) as
   specified in IETF draft-reeder-snmpv3-usm-3desede. Whether or not this works with any particular
   device, we do not know.

FILES
=====

* /etc/munin/munin-node.conf
* /etc/munin/plugin-conf.d/*
* /etc/munin/plugins/*
* /usr/share/munin/plugins/*

SEE ALSO
========

See :ref:`munin` for an overview over munin.
