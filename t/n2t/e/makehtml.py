#! /usr/bin/env python

# Transforms an file written in reStructuredText
# (http://docutils.sourceforge.net/rst.html), to an HTML file.
# This script is just a thin wrapper around the Docutils rst2html
# tool, which is assumed to be in the caller's path.
#
# Usage: makehtml {filename}.rst
#
# Output is written to {filename}.html.
#
# adapted from Greg Janee's code (gjanee@ucop.edu, September 2015)

import re
import subprocess
import sys
import tempfile

def error (message):
  sys.stderr.write("makehtml: %s\n" % message)
  sys.exit(1)

if sys.argv[1] == '--date':
  dopt = '--date'
  sys.argv.pop(1)
else:
  dopt = '--no-datestamp'
# yyy timestamp not showing up in docs

if len(sys.argv) != 3:
  sys.stderr.write("Usage: makehtml {page_slug}.rst Title\n")
  sys.exit(1)

infile = sys.argv[1]
title = sys.argv[2]
slug = infile[:-4] 
outfile = slug + ".html"

t = tempfile.NamedTemporaryFile()
try:
  try:					# try the Mac OS way
    if subprocess.call(["rst2html.py", dopt, infile, t.name]) != 0:
      error("subprocess call failed")
  except OSError:			# try the Linux way
    if subprocess.call(["rst2html", dopt, infile, t.name]) != 0:
      error("subprocess call failed")
except:
  raise
m = re.search("//BEGIN//</p>\n(.*)<p>//END//", t.read(), re.S)
if not m: error("error parsing rst2html output")
body = m.group(1)
t.close()

# Note the hack below: extra </div>'s are needed to close the
# preceding section.

f = open(outfile, "w")
f.write(
"""<!DOCTYPE html>
<html lang="en">
<head>
  <!--#include virtual="/e/prelim.html" -->
  <title>%s</title>
</head>
<body>
<!--#include virtual="/e/header.html" -->
<!--#include virtual="breadcrumb_%s.html" -->
<div class="container-narrowest">
%s
</div>
</div>
</div>
<!--#include virtual="/e/footer.html" -->
</body>
</html>
""" % (title, slug, body))
f.close()
