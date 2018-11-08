#!/bin/bash

pkgname=$1
cur_path=$(dirname "$0")
if [ "$pkgname" = "ipmitool" ]; then
    $cur_path/ipmitool/build.sh
    exit $?
elif [ -z $pkgname ]; then
    echo "Please specify package want to build"
    exit 1
fi
