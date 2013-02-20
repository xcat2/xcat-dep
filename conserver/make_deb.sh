#!/bin/bash

tar xvfz conserver-8.1.16.tar.gz
cd conserver-8.1.16
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf conserver-8.1.16
