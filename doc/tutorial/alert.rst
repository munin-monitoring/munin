.. _tutorial-alert:

=====================
Let Munin croak alarm
=====================

As of Munin 1.2 there is a generic interface for sending warnings
and errors from Munin. If a Munin plugin discovers that a plugin has
a data source breaching its defined limits, Munin is able to alert
the administrator either through simple command line invocations
or through a monitoring system like Nagios or Icinga.

Note that if the receiving system can cope with only
a limited number of messages at the time, the configuration directive
:ref:`contact.contact.max_messages <directive-contact>` may be useful.

When sending alerts, you might find good use in the
`variables available from Munin <http://munin-monitoring.org/wiki/MuninAlertVariables>`_.

.. note:: Alerts not working? For some versions 1.4 and less, note that having `more than one contact defined <http://munin-monitoring.org/ticket/732>`_ can cause munin-limits to hang.

Sending alerts through Nagios
=============================

How to set up Nagios and Munin to communicate has been thoroughly
described in `HowToContactNagios <http://munin-monitoring.org/wiki/HowToContactNagios>`_.

Alerts send by local system tools
=================================

Email Alert
-----------

To send email alerts directly from Munin use a command such as this:

::

 contact.email.command mail -s "Munin-notification for ${var:group} :: ${var:host}" your@email.address.here

For an example with explanation please look at
`Munin alert email notification <http://blog.edseek.com/archives/2006/07/13/munin-alert-email-notification/>`_

Syslog Alert
------------

To send syslog message with priority use a command such as this:

::

 contact.syslog.command logger -p user.crit -t "Munin-Alert"


Alerts to or through external scripts
-------------------------------------

To run a script (in this example, 'script') from Munin use a command such as this in your munin.conf.

Make sure that:

#. There is NO space between the '>' and the first 'script'
#. 'script' is listed twice and
#. The munin user can find the script -- by either using an absolute path or putting the script somewhere on the PATH -- and has permission to execute the script.

::

 contact.person.command >script script

This syntax also will work (this time, it doesn't matter if there is a space
between '|' and the first 'script' ... otherwise, all the above recommendations apply):

::

 contact.person.command | script script

Either of the above will pipe all of Munin's warning/critical
output to the specified script.  Below is an example script
to handle this input and write it to a file:

::

 #!/usr/bin/env ruby

 File.open('/tmp/munin_alerts.log', 'a') do |f| #append
    f.puts Time.now
    for line in $stdin
       f.puts line
    end
 end

The alerts getting piped into your script will look something like this:

::

 localhost :: localdomain :: Inode table usage
        CRITICALs: open inodes is 32046.00 (outside range [:6]).

Syntax of warning and critical
==============================

The ``plugin.warning`` and ``plugin.critical`` values supplied by a plugin
can be overwritten by the Munin master configuration in
:ref:`munin.conf <master-conf-field-directives>`.

Note that the warning/critical exception is raised
only if the value is outside the defined value.
E.g. ``foo.warning 100:200`` will raise a warning only
if the value is outside the range of 100 to 200.

Reformatting the output message
===============================

You can redefine the format of the output message by setting *Global Directive*
:ref:`contact.\<something\>.text <directive-contact>` in :ref:`munin.conf <munin.conf>`
using variables from `Munin variable overview <http://munin-monitoring.org/wiki/MuninAlertVariables>`_.

Something like:

::

 contact.pipevia.command | /path/to/script /path/to/script \
    --cmdlineargs="${var:group} ${var:host} ${var:graph_category} '${var:graph_title}'"

 contact.pipevia.always_send warning critical

 contact.pipevia.text  <munin group="${var:group}" host="${var:host}"\
   graph_category="${var:graph_category}" graph_title="${var:graph_title}" >\
   ${loop< >:wfields <warning label="${var:label}" value="${var:value}"\
     w="${var:wrange}" c="${var:crange}" extra="${var:extinfo}" /> }\
   ${loop< >:cfields <critical label="${var:label}" value="${var:value}"\
     w="${var:wrange}" c="${var:crange}" extra="${var:extinfo}" /> }\
   ${loop< >:ufields <unknown label="${var:label}" value="${var:value}"\
     w="${var:wrange}" c="${var:crange}" extra="${var:extinfo}" /> }\
   </munin>

Calls the script with the command line arguments (as a python list):

::

 ['/path/to/script','/path/to/script','--cmdlineargs="example.com', 'test.example.com', 'disk', 'Disk usage in percent', '']

and the input sent to the script is (whitespace added to break long line):

::

 '<munin group="example.com" host="test.example.com" graph_category="disk" graph_title="Disk usage in percent" >
   <critical label="/home" value="98.41" w=":92" c=":98" extra="" />
 </munin> '


(need for the second ``/path/to/script`` may vary, but this document says it is required)

If something goes wrong:

- check the log file for ``munin-limits.log``.
- remember this script will run as the same user as the cron job that starts :ref:`munin-cron <munin-cron>`.


**Further Info on wiki pages**

- `Use alert variables <http://munin-monitoring.org/wiki/MuninAlertVariables>`_
- `Contact Nagios via NSCA <http://munin-monitoring.org/wiki/HowToContactNagios>`_

