#!/bin/bash

tar xvfz elilo-3.14-source.tar.gz
cd elilo
cp -rL ../debian .
dpkg-buildpackage
cd -
rm -rf elilo
