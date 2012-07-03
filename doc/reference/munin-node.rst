.. _munin-node:

.. program:: munin-node

============
 munin-node
============

"munin-node" is installed on all servers being monitored.

By default, it is started at boot time, listens on port 4949/TCP,
accepts connections from the :ref:`munin master <master-index>`, and
runs :ref:`munin plugins <plugin-index>` on demand.

The configuration file is :ref:`/etc/munin/munin-node.conf
<node-reference>`.

Example configuration
=====================

:: 

  # /etc/munin/munin-node.conf - config-file for munin-node
  #
  
  host_name random.example.org
  log_level 4
  log_file /var/log/munin/munin-node.log
  pid_file /var/run/munin/munin-node.pid
  background 1
  setsid 1
  
  # Which port to bind to;
  
  host [::]
  port 4949
  user root
  group root
  
  # Regexps for files to ignore
  
  ignore_file ~$
  ignore_file \.bak$
  ignore_file %$
  ignore_file \.dpkg-(tmp|new|old|dist)$
  ignore_file \.rpm(save|new)$
  ignore_file \.puppet-bak$
  
  # Hosts to allow
  
  cidr_allow 127.0.0.0/8
  cidr_allow 192.0.2.129/32
