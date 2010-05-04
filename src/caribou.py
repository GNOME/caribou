#!/usr/bin/python
#
# Caribou - text entry and UI navigation application
#
# Copyright (C) 2009 Adaptive Technology Resource Centre
#  * Contributor: Ben Konrath <ben@bagu.org>
# Copyright (C) 2009 Eitan Isaacson <eitan@monotonous.org>
# Copyright (C) 2009 Sun Microsystems, Inc.
#  * Contributor: Willie Walker <william.walker@sun.com>
# Copyright (C) 2009 Flavio Percoco <flaper87@flaper87.org>
#  * Contributor: Flavio Percoco <flaper87@flaper87.org>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by the
# Free Software Foundation; either version 2.1 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License
# for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

from optparse import OptionParser
import gettext
import gtk
import sys

import caribou.window as window
import caribou.keyboard as keyboard
import caribou.main as main

_ = gettext.gettext

if __name__ == "__main__":
    parser = OptionParser(usage="usage: %prog [options]", version="%prog 0.0.2")
    parser.add_option("-d", "--debug",
                      action="store_true", dest="debug", default=False,
                      help="print debug messages on stdout")
    (options, args) = parser.parse_args()

    main.debug = options.debug

    caribou = main.Caribou()
    caribou.window.hide_all()
 
    gtk.main()
