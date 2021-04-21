.. _plugin-gallery:

==============
Plugin Gallery
==============

.. index::
   pair: development; plugin
   pair: plugin; contribute
   pair: plugin; documentation
   pair: plugin; gallery

`In the gallery <https://gallery.munin-monitoring.org/>`_ you can browse description and graph images for our Munin Plugins. It is not ready and complete yet. Example graph images are still missing and many plugins have empty documentation pages (due to missing perldoc sections in the plugin script).

Here some examples pages with graph images:

  * `packages.py <https://gallery.munin-monitoring.org/plugins/munin-contrib/deb_packages.py/>`_ - complete
  * `quota2percent_ <https://gallery.munin-monitoring.org/plugins/munin-contrib/quota2percent_/>`_ - complete
  * `oracle_sysstat <https://gallery.munin-monitoring.org/plugins/munin-contrib/oracle_sysstat/>`_ - complete
  * `ejabberd <https://gallery.munin-monitoring.org/plugins/munin-contrib/ejabberd_resources_/>`_ - Image only, missing perldoc
  * `apache_activity <https://gallery.munin-monitoring.org/plugins/munin-contrib/apache_activity/>`_ - Image only, missing perldoc

The HTML-Presentation is auto-generated in a daily cronjob at our project server. It generates the plugins documentation page, that is accessible via :ref:`munindoc <munindoc>` otherwise. Example graphs for the plugins have to be placed in our github repositories.

See `munin-plugin-gallery <https://github.com/munin-monitoring/munin-plugin-gallery>`_ for the technical details of the plugin gallery website builder.

Help from contributors is welcome. Please take a look at the instructions in the next section below.


Categories
==========

The plugins category is the main navigation criterion of the galley. So the first step of the build procedure is the search for the keyword ``graph_category`` within the plugin scripts and parse the string, that follows in the same line.
It makes things easier if you don't use spaces within in the cagetories name. Please use the character *underscore* instead if a separator is needed.

The following pages contain information and recommendations concerning categories:

* :ref:`graph-category <graph_category>`
* :ref:`Well-known plugin categories <well-known-categories>`
* :ref:`Best Current Practices for good plugin graphs <plugin-bcp>`

Rules for plugin contributors
=============================

To make sure that we can auto-generate the portrait pages for each plugin please pay attention to the following instructions.

1. Add **documentation about your plugin in perldoc style** (`information about perldoc <http://juerd.nl/site.plp/perlpodtut>`_) to show with :ref:`munindoc <munindoc>` and in the `Plugin Gallery <https://gallery.munin-monitoring.org/>`_ on the web. (See :ref:`Best Current Practices <plugin-bcp-documentation>`).

 * Add these sections at the start or end of your plugins script file.

2. Upload the plugins files to `Github contrib directory <https://github.com/munin-monitoring/contrib/tree/master/plugins>`_.

 * Put the plugins script in a subdirectory named after the software or product that it monitors, e.g. apache, mariadb, postfix. In case of plugins targeting specific operating systems, place these in a subdirectory with that name, e.g. ``debian`` or ``vmware``. The directory's name will act as an outline on **2nd level** of the plugin gallery (within the plugin category index pages).

 * **Don't use generic terms as directory name** like "mail". We already use :ref:`generic terms <well-known-categories>` to navigate on the 1st level in the plugin gallery and also in the Munin overview!

3. Choose and upload a Munin generated graph of your plugin for demonstration purpose.

 * Take one in original size of the Munin website plugin page. Please do not upload scaled images. Each image should be a file in PNG format.

 * Place the image in the subdirectory ``example-graphs`` of your plugins directory. This is one level deeper in the file hierarchy.

 * The name of the image file should begin with the name of your plugins script file followed by ``-day.png`` for a daily graph, ``-week.png`` for a weekly graph, ``-month.png`` for a monthly graph, ``-year.png`` for a yearly graph, e.g. ``cpu-day.png`` or ``smart_-month.png``.

4. Upload **more image files** to the subdirectory ``example-graphs`` in PNG-Format if you want **to illustrate** the documentation section **Interpretation**

  * The filename of such an additional image should match the following format *<plugins_name>* ``-n.png`` with ``n`` standing for a digit between 1 and 9, e.g. ``cpu-1.png``
