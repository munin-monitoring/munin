.. _plugin-gallery:

==============
Plugin Gallery
==============

.. index::
   pair: development; plugin
   pair: plugin; contribute
   pair: plugin; documentation
   pair: plugin; gallery

`In the gallery <http://gallery.munin-monitoring.org/>`_ you can browse description and graph images for our Munin Plugins. It is not ready and complete yet. Example graph images are still missing and many plugins have empty documentation pages (due to missing perldoc sections in the plugin script).

Here some examples pages with graph images:

  * `packages.py <http://gallery.munin-monitoring.org/contrib/svn/contrib-master/plugins/apt/deb_packages/deb_packages.py.html>`_ - complete
  * `quota2percent_ <http://gallery.munin-monitoring.org/contrib/svn/contrib-master/plugins/disk/quota2percent_.html>`_ - complete
  * `oracle_sysstat <http://gallery.munin-monitoring.org/contrib/svn/contrib-master/plugins/oracle/oracle_sysstat.html>`_ - complete
  * `ejabberd <http://gallery.munin-monitoring.org/contrib/svn/contrib-master/plugins/ejabberd/ejabberd_resources_.html>`_ - Image only, missing perldoc
  * `apache_activity <http://gallery.munin-monitoring.org/contrib/svn/contrib-master/plugins/apache/apache_activity.html>`_ - Image only, missing perldoc

The HTML-Presentation is auto-generated in a daily cronjob at our project server. It views the plugins documentation page, that is viewed by :ref:`munindoc <munindoc>` otherwise. Example graphs for the plugins have to be placed in our github repositories.

Help from contributors is welcome :-) Have a look at our instructions in the next section on this page.

The gallery has two showrooms. One called `Core Collection <http://gallery.munin-monitoring.org/index.html>`_ for the plugins that we deliver with the distribution of Munin-Node and one called `3rd-Party Collection <http://gallery.munin-monitoring.org/contrib/index.html>`_ for the plugins from the wild, that were uploaded to our Contrib-Repository. Especially the later needs a lot of documentation work and we are happy if you add info in perldoc format and representative example graph images to the contrib repo. The more descriptive content is there, the more helpful the Plugin Gallery will be ~

Categories
==========

The plugins category is the main navigation criterion of the galley. So the first step of the build procedure is the search for the keyword ``graph_category`` within the plugin scripts and parse the string, that follows in the same line.
It makes things easier if you don't use spaces within in the cagetories name. Please use character *underscore* instead if a separator is needed.

The following pages contain info and recommendations concerning categories:

* :ref:`graph-category <graph_category>`
* :ref:`Well-known plugin categories <well-known-categories>`
* :ref:`Best Current Practices for good plugin graphs <plugin-bcp>`

Rules for plugin contributors
=============================

To make sure that we can auto-generate the portrait pages for each plugin please pay attention to the following instructions.

1. Add **documentation about your plugin in perldoc style** (`information about perldoc <http://juerd.nl/site.plp/perlpodtut>`_) to show with :ref:`munindoc <munindoc>` and in the `Plugin Gallery <http://gallery.munin-monitoring.org/>`_ on the web. (See :ref:`Best Current Practices <plugin-bcp-documentation>`).

 * Add these sections at the start or end of your plugins script file.

2. Upload the plugins files to `Github contrib directory <https://github.com/munin-monitoring/contrib/tree/master/plugins>`_.

 * Put the plugins script in a subdirectory named after the software or product that it monitors, e.g. apache, mariadb, postfix. When you wrote a plugin for a special operating system, place it in a directory with that name, e.g. debian, vmware. The directories name will act as outline on **2nd level** of the plugin gallery (within the plugin category index pages).

 * **Don't use generic terms as directory name** like "mail". We already use :ref:`generic terms <well-known-categories>` to navigate on the 1st level in the plugin gallery and also in the Munin overview!

3. Choose and upload a Munin generated graph of your plugin for demonstration purpose.

 * Take one in original size of the Munin website plugin page. Please no the zoomed image! It should be a file in PNG-Format.

 * Place it in the subdirectory ``example-graphs`` of your plugins directory, so one level deeper in the file hierarchy.

 * Its name should begin with the name of your plugins script file followed by ``-day.png`` for a daily graph, ``-week.png`` for a weekly graph, ``-month.png`` for a monthly graph, ``-year.png`` for a yearly graph, e.g. ``cpu-day.png`` or ``smart_-month.png``.

4. Upload **more image files** to the subdirectory ``example-graphs`` in PNG-Format if you want **to illustrate** the documentation section **Interpretation**

  * The filename of such an additional image should match the following format *<plugins_name>* ``-n.png`` with ``n`` standing for a digit between 1 and 9, e.g. ``cpu-1.png``

Current state of the project
============================

We have `scripts to auto-generate the HTML presentation called "Munin Plugin Gallery" <https://github.com/munin-monitoring/munin/tree/master/contrib/plugin-gallery>`_ per daily cronjob. 

ToDo
----

Whenever the scripts fails to find the relationship between plugins and categories, we put these into category 'other'. It would be good to improve the plugins data concerning the category or to improve the parse method to decrease the number of these unrelated plugins.
