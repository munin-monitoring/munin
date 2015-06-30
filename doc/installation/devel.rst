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

query_munin_node

The query_munin_node is used to send commands to the node in a very simple way. Node commands are just args of the tool.

dev_scripts/query_munin_node list
dev_scripts/query_munin_node config cpu
dev_scripts/query_munin_node fetch cpu
