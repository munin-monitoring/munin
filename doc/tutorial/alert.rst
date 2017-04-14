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
:ref:`Munin alert variables <alert_variables>`.

.. note:: Alerts not working? For some versions 1.4 and less, note that having `more than one contact defined <http://munin-monitoring.org/ticket/732>`_ can cause munin-limits to hang.

Sending alerts through Nagios
=============================

How to set up Nagios and Munin to communicate has been thoroughly
described in :ref:`Munin and Nagios <tutorial-nagios>`.

Alerts send by local system tools
=================================

Email Alert
-----------

To send email alerts directly from Munin use a command such as this:

::

 contact.email.command mail -s "Munin-notification for ${var:group} :: ${var:host}" your@email.address.here


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
using :ref:`Munin alert variables <alert_variables>`.

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

For more examples see section :ref:`Example usage <alert_variables_example_usage>` below.

.. _alert_variables:

Munin Alert Variables
=====================

When using Munin's built-in alert mechanisms, lots of variables are available.
Generally, all directives recognized in the :ref:`configuration protocol <plugin_attributes_global>`
and in :ref:`munin.conf <munin.conf>`.conf are available as ``${var:directive}``.
We list some frequently used in the following section.

.. _alert_variable_global:

Group or host or plugin related variables
-----------------------------------------

These are directly available.

============

:Variable: **group**
:Syntax: ``${var:group}``
:Reference: Group name as declared in munin.conf.

============

:Variable: **host**
:Syntax: ``${var:host}``
:Reference: Host name as declared in munin.conf.

============

:Variable: **graph_title**
:Syntax: ``${var:graph_title}``
:Reference: Plugin's title as declared via config protocol or set in munin.conf.

============

:Variable: **plugin**
:Syntax: ``${var:plugin}``
:Reference: Plugin's name as declared via config protocol or set in munin.conf.

============

:Variable: **graph_category**
:Syntax: ``${var:graph_category}``
:Reference: Plugin's category as declared via config protocol or set in munin.conf.

.. _alert_variable_data:

Data source related variables
-----------------------------

The below table lists some variables related to the data fields in a plugin.
To extract these, they must be iterated over, even if there is only one field.
Iteration follows the syntax defined in the Perl module `Text::Balanced <http://search.cpan.org/dist/Text-Balanced/>`_
(sample below the table).

============

:Variable: **{fieldname}.label**
:Syntax: ``${var:label}``
:Reference: Label of the data field as declared via plugin's config protocol or set in munin.conf.

============

:Variable: **{fieldname}.value**
:Syntax: ``${var:value}``
:Reference: Value of the data field as delivered by data fetch

============

:Variable: **{fieldname}.extinfo**
:Syntax: ``${var:extinfo}``
:Reference: Extended info of the field, if declared via plugin's config protocol or set in munin.conf.

============

:Variable: **{fieldname}.warning**
:Syntax: ``${var:wrange}``
:Reference: Numeric range for warning alerts of the field, if declared via plugin's config protocol or set in munin.conf.

============

:Variable: **{fieldname}.critical**
:Syntax: ``${var:crange}``
:Reference: Numeric range for critical alerts of the field, if declared via plugin's config protocol or set in munin.conf.

============

:Variable: **wfields**
:Syntax: ``${var:wfields}``
:Reference: Space separated list of fieldnames with a value outside the warning range as detected by munin-limit.

============

:Variable: **cfields**
:Syntax: ``${var:cfields}``
:Reference: Space separated list of fieldnames with a value outside the critical range as detected by munin-limit.

============

:Variable: **ufields**
:Syntax: ``${var:ufields}``
:Reference: Space separated list of fieldnames with an unknown value as detected by munin-limit.

How variables are expanded
--------------------------

The ``${var:value}`` variables get the correct values from munin-limits prior to expansion of the variable.

Then, the ``${var:*range}`` variables are set from {fieldname}.warning and {fieldname}.critical.

Based on those, ``{fieldname}.label`` occurrences where warning or critical levels are breached
or unknown are summarized into the ``${var:*fields}`` variables.

.. _alert_variables_example_usage:

Example usage
-------------

Note that the sample command lines are wrapped for readability.

**Example 1, iterating through warnings and criticals**

::

 contact.mail.command mail -s "[${var:group};${var:host}] -> ${var:graph_title} ->
                              warnings: ${loop<,>:wfields  ${var:label}=${var:value}} /
                              criticals: ${loop<,>:cfields  ${var:label}=${var:value}}" me@example.com

This stanza results in an e-mail with a subject like this:

::

 [example.com;foo] -> HDD temperature -> warnings: sde=29.00,sda=26.00,sdc=25.00,sdd=26.00,sdb=26.05 / criticals:

Note that there are no breaches of critical level temperatures, only of warning level temperatures.

**Example 2, reading ${var:wfields}, ${var:cfields} and ${var:ufields} directly**

::

 contact.mail.command mail -s "[${var:group};${var:host}] -> ${var:graph_title} ->
                              warnings: ${var:wfields} /
                              criticals: ${var:cfields} /
                              unknowns: ${var:ufields}" me@example.com

The result of this is the following:

::

 [example.com;foo] -> HDD temperature -> warnings: sde sda sdc sdd sdb / criticals: / unknowns:

Iteration using Text::Balanced
------------------------------

The Text::Balanced iteration syntax used in munin-limits is as follows (extra spaces added for readability):

::

 ${ loop < join character > : list of words ${var:label} = ${var:value} }

Given a space separated list of words "a b c", and the join character "," (comma), the output from the above will equal

::

 a.label = a.value,b.label = b.value,c.label = c.value

in which the label and value variables will be substituted by their Munin values.

Please consult the `Text::Balanced <http://search.cpan.org/dist/Text-Balanced/>`_ documentation for more details.
