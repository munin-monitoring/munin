.. _example-webserver-apache-cron:

===========================
 Apache Cron Configuration
===========================

This example describes how to use `Apache <https://httpd.apache.org/>`_ for delivering graphs and
HTML files that were generated via cron.


Virtualhost configuration
=========================

Add a new virtualhost, using the following example:

.. index::
   triple: munin-cron; apache configuration; example

::

   <VirtualHost *:80>
       ServerName munin.example.org
       ServerAlias munin

       ServerAdmin  info@example.org

       DocumentRoot /var/www

       Alias /munin/static/ /etc/munin/static/
       <Directory /etc/munin/static>
           Require all granted
       </Directory>

       Alias /munin /var/cache/munin/www
       <Directory /var/cache/munin/www>
           Require all granted
       </Directory>

       CustomLog /var/log/apache2/munin.example.org-access.log combined
       ErrorLog  /var/log/apache2/munin.example.org-error.log
   </VirtualHost>
