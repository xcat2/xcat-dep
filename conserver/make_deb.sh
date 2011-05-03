#!/bin/bash

tar xvfz conserver-8.1.16.tar.gz
cd conserver-8.1.16
cp -rL ../debian .
dpkg-buildpackage
cd -
rm -rf conserver-8.1.16
