.. _example-webserver-apache:

==================================
 Apache virtualhost configuration
==================================

This example describes how to set up munin on a separate virtual host
using apache httpd. It proxies all requests to :ref:`munin-httpd`

Virtualhost configuration
=========================

Add a new virtualhost, using the following example:

.. index::
   triple: munin-httpd; apache httpd configuration; example

::

 <VirtualHost *:80>
     ServerName munin.example.org
     ServerAlias munin

     ServerAdmin  info@example.org

     DocumentRoot /srv/www/munin.example.org

     ErrorLog  /var/log/apache2/munin.example.org-error.log
     CustomLog /var/log/apache2/munin.example.org-access.log combined

     RewriteEngine On
     RewriteRule ^/(.*\.html)$ /srv/www/munin.example.org/$1          [L]

     # Proxy everything to munin-httpd
     ProxyPass        / http://localhost:4948/
     ProxyPassReverse / http://localhost:4948/
 </VirtualHost>
