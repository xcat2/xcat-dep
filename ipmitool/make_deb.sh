#!/bin/bash

tar xvfz ipmitool-1.8.11.tar.gz
cd ipmitool-1.8.11
cp -rL ../debian .
HOST_ARCH=`uname -m`
if [ "$HOST_ARCH" = "ppc64le" ]; then
    HOST_ARCH="ppc64el"
elif [ "$HOST_ARCH" = "x86_64" ]; then
    HOST_ARCH="amd64"
else
    HOST_ARCH="amd64"
fi
TARGET_ARCH=$HOST_ARCH dpkg-buildpackage -uc -us
cd -
rm -rf ipmitool-1.8.11
