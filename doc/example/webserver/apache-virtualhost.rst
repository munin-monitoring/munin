.. _example-webserver-apache:

==================================
 Apache virtualhost configuration
==================================

This example describes how to set up munin on a separate virtual host
using apache httpd. It proxies all requests to :ref:`munin-httpd`

Munin configuration
===================

This example assumes the following configuration in
/etc/munin/munin.conf

.. index::
   pair: example; munin.conf
   pair: example; graph_strategy
   pair: example; html_strategy

::

 graph_strategy cgi
 html_strategy  cgi

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

     # Proxy everything to munin-httpd
     ProxyPass        / http://localhost:4948/
     ProxyPassReverse / http://localhost:4948/
 </VirtualHost>
