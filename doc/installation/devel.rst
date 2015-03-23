==========================
 Development Environment 
==========================

There is a marvelous `dev_scripts/` directory in the Munin source code. As its
usage is very easy, here is a tutorial about how to use it.

Prerequisites
--------------

To use it, one has to install all the packages needed for munin, and to grab a
copy of the source code. Easiest is to use either a tarball, or to clone the
git repository.

Note that the guidelines on contributing back are specified directly in the git
repo.

Now, I just assume you want to contribute back, otherwise you would not care
much about the said dev environment. That means using the git way of doing it.

Download the source code
------------------------

First step is to clone the git repository. We will use `$HOME/src/munin` as the
development directory.

:: 

        mkdir -p $HOME/src
        cd $HOME/src
        git clone https://github.com/munin-monitoring/munin munin
        cd munin

Compile munin
-------------

Now, we have to compile the source code. I know that it sounds strange as the
code is mostly Perl, but there are some templates that need to be filled with
the environment specifics, such as the Perl interpreter path, a POSIX
compatible shell, ...

::

        dev_scripts/install 1

Now all munin (and munin-node) should be compiled and installed in
`$HOME/src/munin/sandbox`.

Note that the `1` at the end is explained below.
Using the dev tools

There are some different tools in dev_scripts/ :
install

This is the one you used already. You have to use it every time you want to recompile & deploy the package.

The 1 argument, does a full re-install (wipe & install), so you don't usually want to do that.
restart_munin-node

This is a tool to start the development node. Note that it listens on the port 4948, so you can use it alongside a normal munin-node.
run

The run command inside is used to launch all the executable parts of munin, such as munin-update, munin-html or munin-limits. It can also be used to launch munin-run and munin-node-configure.

The usage is very simple, just prefix the command to launch with dev_scripts/run, every environment variable and command line argument will be forwarded to the said command.

# launch munin-cron
dev_scripts/munin-cron

# launch manually some cron parts
dev_scripts/munin-update
dev_scripts/munin-limits
dev_scripts/munin-html
dev_scripts/munin-graph

# debug a plugin
dev_scripts/munin-run --debug cpu config

cgi

This is the same as run, only for CGI. It sets up the whole environment vars that emulates a CGI call. Usage is very easy :

dev_scripts/cgi munin-cgi-graph /localnet/localhost/cpu-day.png > out.dat

The out.dat will contain the whole HTTP output, with the HTTP headers and the PNG content. Everything that is sent to STDERR won't be catched, so you can liberally use it while debugging.
query_munin_node

The query_munin_node is used to send commands to the node in a very simple way. Node commands are just args of the tool.

dev_scripts/query_munin_node list
dev_scripts/query_munin_node config cpu
dev_scripts/query_munin_node fetch cpu

Real CGI usage with your web browser

That's the holy grail. You will have a development version that behaves the same as a real munin install.

First, let's assume you have a working user cgi configuration (ie ~user/cgi/whatever is working). If not you should refer yourself to the local documentation of your preferred webserver. Note that nginx will _not_ work, as it does not support CGI.

I wrote a very simple cgi wrapper script. The home dir is hard coded in the script::

        #! /bin/sh

        ROOT=/home/me/src/munin
        eval "$(perl -V:version)"

        PERL5LIB=$ROOT/sandbox/usr/local/share/perl/$version
        #export DBI_TRACE=2=/tmp/dbitrace.log

        exec perl -T -I $PERL5LIB $ROOT/sandbox/opt/munin/www/cgi/$CGI_NAME
