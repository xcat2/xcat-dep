#!/bin/bash

tar xvfz ipmitool-1.8.11.tar.gz
cd ipmitool-1.8.11
cp -rL ../debian .
dpkg-buildpackage -uc -us
cd -
rm -rf ipmitool-1.8.11
