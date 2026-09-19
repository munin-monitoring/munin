.. _howto-alerts-setup:

===================================
How to set up alerts
===================================

Munin can notify you when monitored values exceed warning or critical
thresholds. This howto covers the most common alert configurations.

Email Alerts
============

The simplest alert setup sends email when values go out of range.

Add to ``/etc/munin/munin.conf``:

::

   contact.email.command mail -s "Munin ${var:worst}: ${var:group}::${var:host}::${var:plugin}" admin@example.com
   contact.email.always_send warning critical

The ``${var:...}`` variables are expanded by ``munin-limits``. The most
useful ones:

- ``${var:group}`` — the group name
- ``${var:host}`` — the host name
- ``${var:plugin}`` — the plugin name
- ``${var:graph_title}`` — the graph title
- ``${var:worst}`` — worst status (OK, WARNING, CRITICAL, UNKNOWN)
- ``${var:label}`` — field label (inside loops)
- ``${var:value}`` — field value (inside loops)

Per-Host Alerts
================

To send alerts for specific hosts only:

::

   contact.email.command mail -s "Munin ${var:worst}: ${var:host}" admin@example.com

   [critical-servers;]
     contacts email

   [critical-servers;db1.example.com]
     address 192.0.2.20
     contacts email

   [critical-servers;web1.example.com]
     address 192.0.2.10
     contacts email

Only hosts under the ``critical-servers`` group will trigger email alerts.

Alerting via Script
====================

To run a custom script (for Slack, PagerDuty, etc.):

::

   contact.slack.command /usr/local/bin/munin-to-slack
   contact.slack.always_send warning critical

The script receives the alert on stdin. Example for a Slack webhook:

.. code-block:: bash

   #!/bin/bash
   read -r payload
   curl -X POST -H 'Content-type: application/json' \
     --data "{\"text\":\"$payload\"}" \
     https://hooks.slack.com/services/YOUR/WEBHOOK/URL

Suppressing Alerts
==================

To disable alerts for a specific host or plugin:

::

   [web1.example.com]
     contacts none

   [web1.example.com]
     nginx.contacts none

The ``none`` value disables all contacts for that scope.

Custom Thresholds
==================

To override a plugin's default thresholds:

::

   [db1.example.com]
     mysql.connections.warning 100
     mysql.connections.critical 200
     disk.usage.warning 80
     disk.usage.critical 95

Threshold syntax:

- Single number: upper limit (``warning 80`` means warn if > 80)
- Colon-separated: range (``warning 20:80`` means warn if < 20 or > 80)

Testing Alerts
===============

To test your alert configuration without waiting for the next cron run:

.. code-block:: bash

   sudo -u munin /usr/share/munin/munin-limits --debug

This shows which contacts would be notified and why.

To force a test alert, temporarily set a very low threshold:

::

   [test-host.example.com]
     load.warning 0.01

After munin-limits runs, remove the test threshold.
