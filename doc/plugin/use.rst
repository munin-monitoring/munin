.. _plugin-use:

=====================
 Using munin plugins
=====================

.. index::
   pair: plugin; installing

Installing
==========

The default directory for plugin scripts is /usr/share/munin/plugins/.
A plugin is activated when you create a symbolic link in the ``servicedir`` 
(usually /etc/munin/plugins/ for a package installation of Munin)
and restart the munin-node daemon.

The utility :ref:`munin-node-configure` is used by Munin installation 
procedure to check which plugins are suitable for your node and 
create the links automatically. You may call it everytime when you
changed something (services, hardware  or configuration) on your
node and want to adjust the collection of plugins accordingly. 
Wenn you removed software start it with option '--remove-also'.

To use a Munin plugin being delivered from a `3rd-Party <http://gallery.munin-monitoring.org/contrib/>`_,
place it in directory ``/usr/local/munin/lib/plugins`` (or in another 
directory of your choice) make it executable and create the service link. 
It may work also, if you put the plugin in the ``servicedir`` directly, 
but this is not recommended to support use of utility 
``munin-node-configure`` and because it is not appropriate for
:ref:`wildcard plugins <tutorial-plugins-wildcard>` and also
to avoid struggle with SELinux.

You may put 3rd-Party plugins in the *official* plugin directory
(usually ``/usr/share/munin/plugins``), but be prepared (Backup!)
against overwriting existing plugin scripts with newer versions
from the distribution.

.. index::
   pair: plugin; configuration

Configuring
===========

plugin-conf.d is the directory with the plugin configuration files. 
When pre-packaged, it's usually located in /etc/munin/, while if 
compiled from source it is often found in /etc/opt/munin/. 

To make sure that you get all new plugin configurations with software updates 
you should not change the file munin-node which is delivered with the munin package.
Instead put your customized configuration in a file called zzz-myconf.
As the config files are read in alphabetical order your file is read 
at last and will override configuration found in the other files.

The file should consist of one or more sections, one section for each 
(group of) plugin(s) that should run with different privileges 
and/or environment variables.

Start a plugins configuration section with the plugins name in square brackets:

[<plugin-name>] 
  The following lines are for <plugin-name>. May include one wildcard ('*') at the start or end of the plugin-name, but not both, and not in the middle.

After that each section can set attributes in the following format, where all attributes are optional. 

user <username|userid>
  Run plugin as this user

  Default: munin

group <groupname|groupid>[, <groupname|groupid>] [...]  
  Run plugin as this group. If group is inside parentheses, the plugin will continue if the group doesn't exist.

  **What does comma separated groups do?** See $EFFECTIVE_GROUP_ID in the `manual page for perlvar <http://perldoc.perl.org/perlvar.html>`_

  Default: munin

env.var <variable content>
  Will cause the environment variable <var> to be set to <contents> when running the plugin. 
  More than one env line may exist. See the individual plugins to find out which variables they care about.

  There is no need to quote the variable content.

host_name <host-name> 
  Forces the plugin to be associated with the given host, overriding anything that "plugin config" may say. 

timeout <seconds> 
  Maximum number of seconds before the plugin script should be killed when fetching values. 
  The default is 10 seconds, but some plugins may require more time. 

command <command> 
  Run <command> instad of plugin. %c will be expanded to what would otherwise have been run. E.g. command sudo -u root %c.

.. note::

   When configuring a munin plugin, add the least amount of extra
   privileges needed to run the plugin. For instance, do not run a
   plugin with "user root" to read syslogs, when it may be sufficient
   to set "group adm" instead.

Examples:

.. index::
   triple: example; plugin; configuration

::

  [mysql*]
  user root
  env.mysqlopts --defaults-extra-file=/etc/mysql/debian.cnf

  [exim_mailqueue]
  group mail, (Debian-exim)

  [exim_mailstats]
  group mail, adm

  [ldap_*]
  env.binddn cn=munin,dc=foo,dc=bar
  env.bindpw secret

  [snmp_*]
  env.community SecretSNMPCommunityString

  [smart_*]               # The following configuration affects 
                          # every plugin called by a service-link starting with smart_
                          # Examples: smart_hda, smart_hdb, smart_sda, smart_sdb
  user root
  group disk

Plugin configuration is optional.

.. index::
   pair: plugin; testing

Testing
=======

To test if the plugin works when executed by munin, you can use the
:ref:`munin-run` command.

.. code-block:: bash

   # munin-run myplugin config

   # munin-run myplugin

   # munin-run -d myplugin

Examples:

::

  # munin-run df_abs config
  graph_title Filesystem usage (in bytes)
  graph_args --base 1024 --lower-limit 0
  graph_vlabel bytes
  graph_category disk
  graph_total Total
  _dev_mapper_vg_demo_lv_root__.label /
  _dev_mapper_vg_demo_lv_root__.cdef _dev_mapper_vg_demo_lv_root__,1024,*
  tmpfs__dev_shm.label /dev/shm
  tmpfs__dev_shm.cdef tmpfs__dev_shm,1024,*
  _dev_vda1__boot.label /boot
  _dev_vda1__boot.cdef _dev_vda1__boot,1024,*
  _dev_mapper_vg_demo_lv_tmp__tmp.label /tmp
  _dev_mapper_vg_demo_lv_tmp__tmp.cdef _dev_mapper_vg_demo_lv_tmp__tmp,1024,*
  _dev_mapper_vg_demo_lv_var__var.label /var
  _dev_mapper_vg_demo_lv_var__var.cdef _dev_mapper_vg_demo_lv_var__var,1024,*


  # munin-run -d df_abs
  # Processing plugin configuration from /etc/munin/plugin-conf.d/df
  # Processing plugin configuration from /etc/munin/plugin-conf.d/fw_
  # Processing plugin configuration from /etc/munin/plugin-conf.d/hddtemp_smartctl
  # Processing plugin configuration from /etc/munin/plugin-conf.d/munin-node
  # Processing plugin configuration from /etc/munin/plugin-conf.d/postfix
  # Processing plugin configuration from /etc/munin/plugin-conf.d/sendmail
  # Setting /rgid/ruid/ to /99/99/
  # Setting /egid/euid/ to /99 99/99/
  # Setting up environment
  # Environment exclude = none unknown iso9660 squashfs udf romfs ramfs debugfs binfmt_misc rpc_pipefs fuse.gvfs-fuse-daemon
  # About to run '/etc/munin/plugins/df_abs'
  _dev_mapper_vg_demo_lv_root__.value 1314076
  tmpfs__dev_shm.value 0
  _dev_vda1__boot.value 160647
  _dev_mapper_vg_demo_lv_tmp__tmp.value 34100
  _dev_mapper_vg_demo_lv_var__var.value 897644

