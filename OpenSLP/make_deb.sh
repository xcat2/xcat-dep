#!/bin/bash

wget "http://downloads.sourceforge.net/project/openslp/OpenSLP/1.2.1/openslp-1.2.1.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fopenslp%2Ffiles%2FOpenSLP%2F1.2.1%2Fopenslp-1.2.1.tar.gz%2Fdownload&ts=1334057514&use_mirror=freefr" -O openslp-1.2.1.tar.gz
tar xvfz openslp-1.2.1.tar.gz
cd openslp-1.2.1
cp -rL ../debian .
dpkg-buildpackage
cd -
rm -rf openslp-1.2.1*
