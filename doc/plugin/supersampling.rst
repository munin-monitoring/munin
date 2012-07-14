.. _plugin-supersampling:

Every monitoring software has a polling rate. It is usually 5 min, because it's the sweet spot that enables frequent updates yet still having a low overhead.

Munin is not different in that respect : it's data fetching routines __have__ to be launched every 5 min, otherwise you'll face data loss. And this 5 min period is deeply grained in the code. So changing it is possible, but very tedious and error prone.

But sometimes we need a very fine sampling rate. Every 10 seconds enables us to track fast changing metrics that would be averaged out otherwise. Changing the whole polling process to cope with a 10s period is very hard on hardware, since now __every__ update has to finish in these 10 seconds. 

This triggered an extension in the plugin protocol, commonly known as ''supersampling''.

Supersampling
=============

Overview
--------


The basic idea is that fine precision should only be for selected plugins only. It also cannot be triggered from the master, since the overhead would be way too big. 

So, we just let the plugin sample itself the values at a rate it feels adequate. Then each polling round, the master fetches all the samples since last poll. 

This enables various constructions, mostly around ''streaming'' plugins to achieve highly detailed sampling with a very small overhead.

Notes
+++++

This protocol is currently completely transparent to @@munin-node@@, and therefore it means that it can be used even on older (1.x) nodes. Only a 2.0 master is required.

Protocol details
----------------

The protocol itself is derived from the spoolfetch extension.

Config
++++++

A new directive is used, @@update_rate@@. It enables the master to create the rrd with an adequate step. 

Omitting it would lead to rrd averaging the supersampled values onto the default 5 min rate. This means **data loss**.

Notes
#####

The heartbeat has always a 2 step size, so failure to send all the samples will result with unknown values, as expected. 

The RRD file size is always the same in the default config, as all the RRA are configured proportionally to the @@update_rate@@. This means that, since you'll keep as much data as with the default, you keep it for a shorter time.

Fetch
+++++

When spoolfetching, the epoch is also sent in front of the value. Supersampling is then just a matter of sending multiple epoch/value lines, with monotonically increasing epoch. Note that since the epoch is an integer value for rrdtool, the smallest granularity is 1 second. For the time being, the protocol itself does also mandates integers. We can easily imagine that with another database as backend, an extension could be hacked together. 

Compatibility with 1.4
----------------------

On older 1.4 masters, only the last sampled value gets into the rrd.

Sample implementation
---------------------

The canonical sample implementation is multicpu1sec, a contrib plugin on github. It is also a so-called streaming plugin. 

Streaming plugins
-----------------

These plugins fork a background process when called that streams a system tool into a spool file. In multipcu1sec, it is the @@mpstat@@ tool with a period of 1 second.

Undersampling
=============

Some plugins are on the opposite side of the spectrum, as they only need a lower precision. 

It makes sense when : 

* data should be kept for a *very* long time
* data is *very* expensive to generate and it varies only slowly.
