#!/usr/bin/env python

from distutils.core import setup
from subprocess import Popen, PIPE


# Get the current revision from SVN
try:
    p = Popen(['svnversion'], stdout=PIPE)
    version = p.stdout.read().strip()
except OSError:
    version = "unknown"

setup(name="python-munin",
      version=version,
      url="http://dev.sbhr.dk/svn/python-munin",
      author="Morten Siebuhr",
      author_email="sbhr@sbhr.dk",
      description="",
      # packages=['munin'],
      py_modules=['munin'])
