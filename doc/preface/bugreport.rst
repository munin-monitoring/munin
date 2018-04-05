=========================
Bug Reporting Guidelines
=========================

When you find a bug in Munin we want to hear about it. Your bug reports
play an important part in making Munin more reliable because even the
utmost care cannot guarantee that every part of Munin will work on every
platform under every circumstance.

The following suggestions are intended to assist you in forming bug reports
that can be handled in an effective fashion. No one is required to follow them
but doing so tends to be to everyone's advantage.

We cannot promise to fix every bug right away. If the bug is obvious, critical,
or affects a lot of users, chances are good that someone will look into it. It
could also happen that we tell you to update to a newer version to see if the
bug happens there. Or we might decide that the bug cannot be fixed before some
major rewrite we might be planning is done. Or perhaps it is simply too hard
and there are more important things on the agenda. If you need help
immediately, consider obtaining a commercial support contract.

Identifying Bugs
================

Before you report a bug, please read and re-read the documentation to verify
that you can really do whatever it is you are trying. If it is not clear from
the documentation whether you can do something or not, please report that too;
it is a bug in the documentation. If it turns out that a program does something
different from what the documentation says, that is a bug. That might include,
but is not limited to, the following circumstances:

- A program terminates with a fatal signal or an operating system error message
  that would point to a problem in the program. (A counterexample might be a
  "disk full" message, since you have to fix that yourself.)

- A program produces the wrong output for any given input.

- A program refuses to accept valid input (as defined in the documentation).

- A program accepts invalid input without a notice or error message. But keep
  in mind that your idea of invalid input might be our idea of an extension or
  compatibility with traditional practice.

- Munin fails to compile, build, or install according to the instructions on
  supported platforms.

Here "program" refers to any executable, not only the back-end process.

Being slow or resource-hogging is not necessarily a bug. Read the documentation
or ask on one of the mailing lists for help in tuning your applications.

Before you continue, check on the TODO list and in the FAQ to see if your bug
is already known. If you cannot decode the information on the TODO list, report
your problem. The least we can do is make the TODO list clearer.

What to Report
==============

The most important thing to remember about bug reporting is to state all the
facts and only facts. Do not speculate what you think went wrong, what "it
seemed to do", or which part of the program has a fault. If you are not
familiar with the implementation you would probably guess wrong and not help us
a bit. And even if you are, educated explanations are a great supplement to but
no substitute for facts. If we are going to fix the bug we still have to see it
happen for ourselves first. Reporting the bare facts is relatively
straightforward (you can probably copy and paste them from the screen) but all
too often important details are left out because someone thought it does not
matter or the report would be understood anyway.

The following items should be contained in every bug report:

- The exact sequence of steps from program start-up necessary to reproduce the
  problem. This should be self-contained; it is not enough to send in a bare
  log output without the plugin `config` and `fetch` statements.

- The best format for a test case for a restitution issue (graphing or HTML) is
  a sample plugin that can be run through a single munin install that shows the
  problem.  (Be sure to not depend on anything outside your sample plugin). You
  are encouraged to minimize the size of your example, but this is not
  absolutely necessary. If the bug is reproducible, we will find it either way.

- The output you got. Please do not say that it "didn't work" or "crashed". If
  there is an error message, show it, even if you do not understand it. If the
  program terminates with an operating system error, say which. If nothing at
  all happens, say so. Even if the result of your test case is a program crash
  or otherwise obvious it might not happen on our platform. The easiest thing
  is to copy the output from the terminal, if possible.

.. Note::
        If you are reporting an error message, please obtain the most verbose
        form of the message. Use the `--debug` command line arg.

- The output you expected is very important to state. If you just write "This
  command gives me that output." or "This is not what I expected.", we might
  run it ourselves, scan the output, and think it looks OK and is exactly what
  we expected. We should not have to spend the time to decode the exact
  semantics behind your commands. Especially refrain from merely saying that
  "This is not what Cacti/Collectd/... does."

- Any command line options and other start-up options, including any relevant
  environment variables or configuration files that you changed from the
  default. Again, please provide exact information. If you are using a
  prepackaged distribution that starts the database server at boot time, you
  should try to find out how that is done.

- Anything you did at all differently from the installation instructions.

- The Munin version. If you run a prepackaged version, such as RPMs, say so,
  including any Subversion the package might have. If you are talking about a
  Git snapshot, mention that, including the commit hash.

- If your version is older than 2.0.x we will almost certainly tell you to
  upgrade. There are many bug fixes and improvements in each new release, so it
  is quite possible that a bug you have encountered in an older release of
  Munin has already been fixed. We can only provide limited support for
  sites using older releases of Munin; if you require more than we can
  provide, consider acquiring a commercial support contract.

- Platform information. This includes the kernel name and version, perl version,
  processor, memory information, and so on. In most cases it is sufficient to
  report the vendor and version, but do not assume everyone knows what exactly
  "Debian" contains or that everyone runs on amd64.

Where to Report
===============

In general fill in the bug report web-form available at the project's
:ref:`GitHub<github>`.

If your bug report has security implications and you'd prefer that it not
become immediately visible in public archives, don't send it to bugs. Security
issues can be reported privately to <security@munin-monitoring.org>.

Do not send bug reports to any of the :ref:`user mailing lists <mailing-lists>`.
These mailing lists are for answering user questions, and their subscribers normally
do not wish to receive bug reports. More importantly, they are unlikely to fix them.
If you have some doubts about your issue being a bug, just drop by on :ref:`IRC`
and ask there first.

If you have a problem with the documentation, the best place to report it is on
:ref:`IRC` where most of the devs hang out. Please be specific about what part
of the documentation you are unhappy with.

.. Note::

        Due to the unfortunate amount of spam going around, all of the above
        email addresses are closed mailing lists. That is, you need to be
        subscribed to a list to be allowed to post on it.

        If you would like to send mail but do not want to receive list traffic,
        you can subscribe and set your subscription option to nomail.
