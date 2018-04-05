.. _webserver:

=========================
 Webserver Configuration
=========================


Configure web server
====================

On the master, you need to configure a web server.

If you have installed "munin" through distribution
packages, a webserver may have been configured for you already.

If you installed from source, you may want to take a look at the following examples:

=============================================================================== ======================
Mode of Operation                                                               Example Configurations
=============================================================================== ======================
Generate graphs and HTML pages on demand (recommended)                          :ref:`apache <example-webserver-apache-cgi>`
Periodically generate graphs and HTML pages                                     :ref:`apache <example-webserver-apache-cron>` / :ref:`nginx <example-webserver-nginx-cron>`
Proxy connections to separate :ref:`munin-httpd` process (Munin 2.999 or later) :ref:`apache <example-webserver-apache-proxy>` / :ref:`nginx <example-webserver-nginx-proxy>` / :ref:`lighttpd <example-webserver-lighttpd-proxy>`
=============================================================================== ======================
