#!/bin/bash

pkgname=$1
cur_path=$(dirname "$0")
if [ "$pkgname" ]; then
    $cur_path/$pkgname/build.sh
    exit $?
else
    # TODO: if not specify, build all packages for xcat-dep
    echo "Please specify package want to build"
    exit 1
fi
