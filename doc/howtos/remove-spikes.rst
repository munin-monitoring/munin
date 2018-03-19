.. _remove-spikes:

====================
How to remove spikes
====================

.. index::
   pair: RRD; spikes;

If a plugins field is initially created with datatype ``COUNTER`` and no declaration of a ``.max`` value, there may occur spikes in the back-end RRD database when the counter goes back to zero. Here we show a simple way to fix this.

Set a MAX value
===============

First, the plugins config **must** be enhanced to present a ``.max`` value.

Once this has been accomplished and the Munin master has polled the plugin at least once, the masters datafile will have the ``.max`` value stored for the plugin.

Then the following perl 1-liner can be used to update all matching RRDs. Replace *DOMAIN* with the name of the Munin domain being polled, and replace *PLUGIN* with the name of the plugins RRD database files that need updating.

::

  cd /var/lib/munin/DOMAIN
  perl -ne 'next unless /:PLUGIN/; if (/.*;(\S+):(\S+)\.(\S+)\.max\s+(\d+)/) {foreach (glob "$1-$2-$3-?.rrd") {print qq{File: $_\tMax: $4\n};qx{rrdtool tune $_ -a 42:$4};qx{rrdtool dump $_ > /tmp/rrdtool-xml};qx{mv $_ $_.bak};qx{rrdtool restore -r /tmp/rrdtool-xml $_};qx{chown munin:munin $_}}}' ../datafile

An example, updating the *MAX* value in all the ``xvm_`` plugins that have been updated to report a ``.max`` value:

::

  cd /var/lib/munin/example.com
  perl -ne 'next unless /:xvm_/; if (/.*;(\S+):(\S+)\.(\S+)\.max\s+(\d+)/) {foreach (glob "$1-$2-$3-?.rrd") {print qq{File: $_\tMax: $4\n};qx{rrdtool tune $_ -a 42:$4};qx{rrdtool dump $_ > /tmp/rrdtool-xml};qx{mv $_ $_.bak};qx{rrdtool restore -r /tmp/rrdtool-xml $_};qx{chown munin:munin $_}}}' ../datafile
  File: ic5.example.com-xvm_arch4-xvm_arch4_read_bytes-c.rrd    Max: 34359738352
  File: ic6.example.com-xvm_arch3-xvm_arch3_read_bytes-c.rrd    Max: 34359738352
  File: ic3.example.com-xvm_dwork-xvm_dwork_write_bytes-c.rrd   Max: 25769803764


Modify the RRD files concerned
==============================

.. note:: The following is a distillation of the process, outlined [#]_ by Greg Connor in 2004-05-06.


Here is a quick recipe for getting rid of spikes.

In this example *dnscache* is the name of the plugin and *dns1.example.com* is one of the affected hosts.

The desired MAX value is 1000.

Verify that the plugin now sets the right ``.max`` parameter. Fix the plugin if needed.

::

  # cd /var/lib/munin
  # cat datafile | grep dnscache | grep max

View the rrd file with "rrdtool info"

::

  # rrdtool info DNS/dns1.example.com-dnscache-cache-c.rrd

to look for

::

  ds[42].max = NaN


This indicates that the plugin didn't have a ``.max`` defined at the time the rrd file was started. If you don't mind losing the data, you can delete the RRD files at this point and the new ones will be created with the right max.

If you want to save the data, first modify each .rrd file so that it has a max for datasource 42 (not sure why it is always 42, probably a tribute to d.adams) (Best to do this right after an update like at :06 :11 or so)

::

  # bash
  # for j in `find /var/lib/munin -name "*dnscache*-c.rrd"`; do \
  rrdtool tune $j -a 42:1000;
  done

.. note:: Replace 1000 with the desired MAX value.

Finally, dump each rrd file to xml and restore with -r flag. There will be some output to let you know which data points were dropped and replaced with NaN.

::

  # bash
  # for j in `find /var/lib/munin -name "*dnscache*-c.rrd"`; do
  rrdtool dump $j > /tmp/xml ;
  mv $j $j~ ;
  rrdtool restore -r /tmp/xml $j;
  chown munin:munin $j ;
  done

If you are impatient, rebuild one host's graphs and look at it, or just wait 5 min and check.

::

  # su munin -c "/usr/share/munin/munin-graph --nolazy --host DNSOverview "


----

.. [#] See the `post to munin-user mailing list by Greg Connor <https://sourceforge.net/p/munin/mailman/message/4317396/>`_.
