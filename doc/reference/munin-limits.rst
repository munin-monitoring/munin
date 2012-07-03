.. _munin-limits:

.. program:: munin-limits

==============
 munin-limits
==============

"munin-limits" is one of the processes regularly run from the
:ref:`munin-cron` script.

It reads the last collected values for each plugin from the RRD files,
and compares them to the plugin's warning and critical values (if
any). If the limits are breached, it sends an event to any configured
contacts.
