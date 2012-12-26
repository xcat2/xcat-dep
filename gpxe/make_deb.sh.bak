#!/bin/bash

tar xvfj gpxe-1.0.1.tar.bz2
cd gpxe-1.0.1
cp -rL ../debian .
dpkg-buildpackage
cd -
rm -rf gpxe-1.0.1
