#!/bin/bash

tar xvfz conserver-8.2.1.tar.gz
cd conserver-8.2.1
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf conserver-8.2.1
