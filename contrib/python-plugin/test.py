#!/usr/bin/env python

"""
Makes it easy to create munin plugins...

    http://munin-monitoring.org/wiki/protocol-config

Morten Siebuhr
sbhr@sbhr.dk
12/12 2008
"""

from munin import Plugin

p = Plugin("Approx cache", "files", "Approx")
p.info = "Shows how many files the Approx cache stores, split by file-type."


def test(data_source):
    if data_source == 'deb':
        return 42
    return 24


# Set up graph
p['deb'].label = "deb files"
p['deb'].value = test
p['deb'].info = "Number of .deb-files."
p['tar.gz'].label = "tar.gz files"
p['tar.gz'].value = test
# p['gzip'].value = 123

# Run
print("AUTOCONFIG")
p.run("autoconf")

print("CONFIG")
p.run("config")

print("PLAIN")
p.run()
