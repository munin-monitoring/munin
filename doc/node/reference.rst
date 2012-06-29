.. _node-reference:

=======================
 Munin node  reference
=======================


Command line options
====================

+------------+-------------------------------------------+----------------------------+
| option     | explanation                               | default                    |
+============+===========================================+============================+
| --config   | Use <file> as a configuration file        | --config                   |
| <file>     |                                           | /etc/munin/munin-node.conf |
+------------+-------------------------------------------+----------------------------+
| --paranoia | Only run plugins owned by root.           | disabled                   |
+------------+-------------------------------------------+----------------------------+
| --debug    | View debug messages.  May be very verbose | disabled                   |
+------------+-------------------------------------------+----------------------------+
| --pidebug  | Plugin debug.  Sets the environment       | disabled                   |
|            | variable MUNIN_DEBUG to 1, so that        |                            |
|            | plugins may emit debugging information.   |                            |
+------------+-------------------------------------------+----------------------------+

Configuration options
=====================

The directives "host_name", "paranoia" and "ignore_file" are munin node
specific.

All other directives in are passed through to the Perl module Net::Server.
Depending on the version, you may have different settings available, but the
most common are:

+-------------+-----------------------------------+----------------+
| directive   | explanation                       | default value  |
+=============+===================================+================+
| log_level   | Ranges from 0-4. Specifies        | 2              |
|             | what level of error will be       |                |
|             | logged. "0" means no logigng,     |                |
|             | while "4" means very verbose.     |                |
|             | These levels correlate to         |                |
|             | syslog levels as defined by       |                |
|             | the following key/value pairs.    |                |
|             | 0=err, 1=warning, 2=notice,       |                |
|             | 3=info, 4=debug                   |                |
+-------------+-----------------------------------+----------------+
| log_file    | Where the munin node logs its     | undef          |
|             | activity. If the value is         | (STDERR)       |
|             | Sys::Syslog, logging is sent      |                |
|             | to syslog                         |                |
+-------------+-----------------------------------+----------------+
| port        | The TCP port the munin node       | 4949           |
|             | listens on                        |                |
+-------------+-----------------------------------+----------------+
| pid_file    | The pid file of the process       | undef          |
|             |                                   | (none)         |
+-------------+-----------------------------------+----------------+
| background  | To run munin node in background   |                |
|             | set this to "1".  If you want     |                |
|             | munin-node to run as a foreground |                |
|             | process, comment this line out    |                |
|             | and set "setsid" to "0"           |                |
+-------------+-----------------------------------+----------------+
| host        | The IP address the munin node     | All interfaces |
|             | process listens on                |                |
+-------------+-----------------------------------+----------------+
| user        | The user munin-node runs as       | root           |
+-------------+-----------------------------------+----------------+
| group       | The group munin-node runs as      | root           |
+-------------+-----------------------------------+----------------+
| setsid      | If "1", the server forks after    | undef          |
|             | binding to release itself from    |                |
|             | the command line, and runs the    |                |
|             | POSIX::setsid() command to        |                |
|             | daemonize.                        |                |
+-------------+-----------------------------------+----------------+
| ignore_file | Files to ignore when locating     |                |
|             | installed plugins. May be         |                |
|             | repeated.                         |                |
+-------------+-----------------------------------+----------------+
| host_name   | The hostname used by munin-node   |                |
|             | to present itself to the munin    |                |
|             | master.  Use this if the local    |                |
|             | node name differs from the        |                |
|             | name configured in the munin      |                |
|             | master.                           |                |
+-------------+-----------------------------------+----------------+
| allow       | A regular expression defining     |                |
|             | which hosts may connect to the    |                |
|             | munin node.                       |                |
|             |                                   |                |
|             | Use cidr_allow if available.      |                |
+-------------+-----------------------------------+----------------+
| cidr_allow  | Allowed hosts given in CIDR       |                |
|             | notation (192.0.2.1/32). Replaces |                |
|             | or complements "allow".  Not      |                |
|             | supported by old versions of      |                |
|             | Net::Server                       |                |
+-------------+-----------------------------------+----------------+
| cidr_deny   | Like cidr_allow, but used for     |                |
|             | denying host access               |                |
+-------------+-----------------------------------+----------------+
| timeout     | Number of seconds after the last  | 20 seconds     |
|             | activity by the master until the  |                |
|             | node will close the connection.   |                |
|             |                                   |                |
|             | If plugins take longer to run,    |                |
|             | this may disconnect the master.   |                |
+-------------+-----------------------------------+----------------+
