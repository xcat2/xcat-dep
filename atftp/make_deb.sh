#!/bin/bash

tar xvfz atftp_0.7.dfsg.orig.tar.gz
cd atftp-0.7.dfsg
rm -rf debian
cp -rL ../debian .
dpkg-buildpackage
cd -
rm -rf atftp-0.7.dfsg
