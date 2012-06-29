===============
 Prerequisites
===============

In order for you to install Munin you must have the following:

Building munin
==============

In order to build munin, you need:

* GNU Make — Please do not attempt to use any other make.

* A reasonable Perl 5 (Version 5.8 or newer)

* Perl modules: Module::Build

Developers / packagers need

* Test::MockModule
* Test::MockObject
* Test::Pod::Coverage
* Test::Perl::Critic 1.096 or later
* Test::Exception
* Directory::Scratch (err, wherefrom?)

In order to build the documentation, you need:
* sphinx

Running munin
=============

In order to run munin, you need:

* A reasonable perl 5 (Version 5.8 or newer)

The munin node needs:

* Perl modules

  * Net::Server
  * Net::Server::Fork
  * Time::HiRes
  * Net::SNMP (Optional, if you want to use SNMP plugins)

* Java JRE (Optional, if you want to use java plugins)
* Anything the separate plugins may need. These have diverse
  requirements, not documented here.

The munin master needs

* Perl modules:

    * CGI::Fast
    * Digest::MD5,
    * File\::Copy::Recursive
    * Getopt::Long
    * HTML::Template
    * IO::Socket::INET6
    * Log::Log4perl 1.18 or later
    * Net::SSLeay (Optional, if you want to use SSL/TLS)
    * Params::Validate
    * Storable
    * Text::Balanced
    * Time::HiRes
    * TimeDate

* A web server capable of CGI or FastCGI
