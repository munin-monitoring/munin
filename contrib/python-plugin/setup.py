#!/usr/bin/env python

from distutils.core import setup
from subprocess import Popen, PIPE

from glob import glob

# Get the current revision from SVN
try:
    p = Popen(['svnversion'], stdout=PIPE)
    version = p.stdout.read().strip()
except:
    version = "unknown"

setup(
        name = "python-munin",
        version = version,
        url = "http://dev.sbhr.dk/svn/python-munin",
        author = "Morten Siebuhr",
        author_email = "sbhr@sbhr.dk",
        description = "",
        #packages = ['munin'],
        py_modules = ['munin'],
    )
