#!/bin/bash

tar xvfj xnba-1.0.3.tar.bz2 
cd xnba-1.0.3
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf xnba-1.0.3 
