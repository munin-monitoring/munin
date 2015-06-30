.. _example-rrdcached-upstart:

=====================================
 Upstart configuration for rrdcached
=====================================

This example sets up a dedicated rrdcached instance for munin.

If rrdcached stops, it is restarted.

A pre-start script ensures we have the needed directories

A post-start script adds permissions for the munin fastcgi process. This assumes that your fastcgi
graph process is running as the user "www-data", and that the file system is mounted with "acl".

::

    description "munin instance of rrdcached"
    author "Stig Sandbeck Mathisen <ssm@fnord.no>"

    start on filesystem
    stop on runlevel [!2345]

    # respawn
    umask 022

    pre-start script
      install -d -o munin -g munin -m 0755 /var/lib/munin/rrdcached-journal
      install -d -o munin -g munin -m 0755 /run/munin
    end script

    script
      start-stop-daemon \
            --start \
            --chuid munin \
            --exec /usr/bin/rrdcached \
            --pidfile /run/munin/rrdcached.pid \
            -- \
            -g \
            -p /run/munin/rrdcached.pid \
            -B -b /var/lib/munin/ \
            -F -j /var/lib/munin/rrdcached-journal/ \
            -m 0660 -l unix:/run/munin/rrdcached.sock \
            -w 1800 -z 1800 -f 3600
    end script

    post-start script
      sleep 1
      setfacl -m u:www-data:rw /run/munin/rrdcached.sock
    end script
