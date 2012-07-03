.. _munin-update:

.. program:: munin-update

==============
 munin-update
==============

.. object:: DESCRIPTION

   munin-update is the primary Munin component. It is run from the
   :ref:`munin-cron` script.

   This script is responsible for contacting all the agents
   (munin-nodes) and collecting their data. Upon fetching the data,
   munin-update stores everything in RRD files - one RRD files for
   each field in each plugin.

   Running munin-update with the --debug flag will often give plenty
   of hints on what might be wrong. 

   munin-update is a component in the Munin server.
