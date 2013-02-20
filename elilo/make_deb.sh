#!/bin/bash

tar xvfz elilo-3.14-source.tar.gz
cd elilo
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf elilo
