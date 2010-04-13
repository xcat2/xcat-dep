#!/bin/bash


#--------------------------------------------------------------------------
# Get oriented 
#--------------------------------------------------------------------------
BUILD=$PWD

#--------------------------------------------------------------------------
# Prepare environment
#--------------------------------------------------------------------------
rm -rf $BUILD/variable 2>/dev/null
mkdir -p $BUILD/variable 2>/dev/null

echo "%_topdir $BUILD" > $BUILD/variable/.rpmmacros
cp $BUILD/variable/.rpmmacros $HOME 2>/dev/null

#---------------------------------------------------------------------------
# Create tar file of zVM MAP agent code
#---------------------------------------------------------------------------
cd $BUILD/ 2>/dev/null

rm -rf $BUILD/BUILD 2>/dev/null
rm -rf $BUILD/RPMS 2>/dev/null
rm -rf $BUILD/SOURCES 2>/dev/null
rm -rf $BUILD/SPECS 2>/dev/null
rm -rf $BUILD/SRPMS 2>/dev/null

mkdir -p $BUILD/BUILD 2>/dev/null
mkdir -p $BUILD/RPMS 2>/dev/null
mkdir -p $BUILD/SOURCES 2>/dev/null
mkdir -p $BUILD/SPECS 2>/dev/null
mkdir -p $BUILD/SRPMS 2>/dev/null

#---------------------------------------------------------------------------
# Copy source and build files into input directories
#---------------------------------------------------------------------------
tar -zcvf $BUILD/zhcp-build.tar.gz zhcp-build 2>/dev/null
mv $BUILD/zhcp-build.tar.gz $BUILD/SOURCES
cp $BUILD/zhcp.spec $BUILD/SPECS 2>/dev/null

#---------------------------------------------------------------------------
# Build the RPM
#---------------------------------------------------------------------------
rpmbuild -ba -v $BUILD/SPECS/zhcp.spec > $BUILD/rpmbuild.log 2>&1

