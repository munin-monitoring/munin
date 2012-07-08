.. _munin-cgi-html:

.. program:: munin-cgi-html

================
 munin-cgi-html
================

.. object:: NAME

   munin-cgi-html — Create HTML pages dynamically

.. object:: DESCRIPTION

   The munin-cgi-html program is intended to be run from a web server.
   It can either run as CGI, or as FastCGI.

.. object:: OPTIONS

   munin-cgi-html takes no options. It is controlled using environment
   variables.

.. object:: ENVIRONMENT VARIABLES

   The following environment variables are used to control the output
   of munin-cgi-html:

   .. OPTION:: PATH_INFO

      This is the remaining part of the URI, after the path to the
      munin-cgi-html script has been removed.

      The group, host, service and timeperiod values are extracted
      from this variable. The group may be nested.

.. object:: PATH_INFO EXAMPLES

   "/" refers to the top page.

   "/example.com/" refers to the group page for "example.com" hosts.

   "/example.com/client.example.com/" refers to the host page for
   "client.example.com" in the "example.com" group

.. object:: COMMAND-LINE EXAMPLES

   When given an URI like the following:
   http://munin.example.org/cgi-bin/munin-cgi-html/example.org

   munin-cgi-html will be called with the following environment:

   PATH_INFO=/example.org

   To verify that munin is able to create HTML pages, you can use the
   following command line:

   .. code-block:: bash

      sudo -u www-data \
      PATH_INFO=/example.org \
      /usr/lib/cgi-bin/munin-cgi-html
