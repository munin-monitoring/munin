.. _develop-tests:

=========================
 Munin development tests
=========================


Scope
=====

The tests we use check for different things.

* Is function x in module y working as expected?
* Can we establish an encrypted network connection between two
  components?
* Do we follow the perl style guidelines?
* Does this component scale well?

The code tests are broadly separated by scope.

Inspired by
https://pages.18f.gov/automated-testing-playbook/principles-practices-idioms/

Small
-----

In this category, we place tests for simple classes and functions,
preferably with fast execution and without using external resources.

Medium
------

Enabled with the TEST_MEDIUM variable set.

In this category, we test interaction between components.  These may
use the file system, fork processes, or access test data sets.

Large
-----

Enabled with the TEST_LARGE variable set.

In this category, we may test the entire system.

A munin master, node, and plugins all running together would be placed
in this category.

Performance and bottleneck testing would also be at home in this
category.
