#!/bin/python

import sys
import errno
import os

from lxml import html

if (len (sys.argv) < 3):
	sys.exit (errno.EINVAL)
elif (len (sys.argv) > 3):
	sys.exit (errno.E2BIG)

if (os.path.isfile (sys.argv[1]) == False):
	sys.exit (errno.EINVAL)

tree = html.parse(sys.argv[1])
results = tree.xpath(sys.argv[2])

if (len (results) > 0):
    print (results[0])
