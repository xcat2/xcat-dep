#!/bin/bash

tar xvfj dpkg_1.15.5.6.tar.bz2
cd dpkg-1.15.5.6
dpkg-buildpackage
cd -
rm -rf dpkg-1.15.5.6
