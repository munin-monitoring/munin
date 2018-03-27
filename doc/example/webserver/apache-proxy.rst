.. _example-webserver-apache-proxy:

============================
 Apache Proxy Configuration
============================

This example describes how to run a separate :ref:`munin-httpd` process and proxy all requests
via `Apache <https://httpd.apache.org/>`_ to this instance.


Virtualhost configuration
=========================

Add a new virtualhost, using the following example:

.. index::
   triple: munin-httpd; apache configuration; example

::

 <VirtualHost *:80>
     ServerName munin.example.org
     ServerAlias munin

     ServerAdmin  info@example.org

     DocumentRoot /srv/www/munin.example.org

     ErrorLog  /var/log/apache2/munin.example.org-error.log
     CustomLog /var/log/apache2/munin.example.org-access.log combined

     # serve static files directly
     RewriteEngine On
     RewriteRule ^/(.*\.html)$ /srv/www/munin.example.org/$1          [L]

     # Proxy everything to munin-httpd
     ProxyPass        / http://localhost:4948/
     ProxyPassReverse / http://localhost:4948/
 </VirtualHost>
