#!/bin/bash

tar xvfj syslinux-3.86.tar.bz2
cd syslinux-3.86
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf syslinux-3.86
