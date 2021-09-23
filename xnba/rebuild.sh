#!/bin/bash

tar xvf ./xnba-1.21.1.tar.bz2
cd xnba-1.21.1 
cp -rL ../debian .
dpkg-buildpackage -uc -us  -aamd64 
cd -
rm -rf xnba-1.21.1 
cp `pwd`/debian/`dh_listpackages`/tftpboot/xcat/xnba.kpxe `pwd`/binary/
cp `pwd`/debian/`dh_listpackages`/tftpboot/xcat/xnba.efi  `pwd`/binary/
