#!/bin/bash
set -e

tar xvfj syslinux-3.86.tar.bz2
cd syslinux-3.86
cp -rL ../debian .

# GCC >= 10 defaults to -fno-common; syslinux 3.86 relies on common symbols
# GCC 15 promotes implicit-function-declaration and incompatible-pointer-types to errors
sed -i '/^GCCWARN := -W -Wall/s/$/ -fcommon -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion/' MCONFIG

# glibc >= 2.28 moved major()/minor() to sys/sysmacros.h
# extlinux/main.c:843 calls major()/minor() unconditionally in 3.86
sed -i '/#include <sys\/types.h>/a #include <sys/sysmacros.h>' extlinux/main.c

# com32/cmenu/Makefile uses python2 menugen.py for test .menu files — not needed for build
rm -f com32/cmenu/*.menu

# vpd.c:67 passes &vpd->base_address (char(*)[6]) not char*; format %X wrong for char* arg
sed -i 's/snprintf(&vpd->base_address, 5, "%X", q)/snprintf(vpd->base_address, sizeof(vpd->base_address), "%s", q)/' com32/gpllib/vpd/vpd.c

export NO_WERROR=1
dpkg-buildpackage -uc -us

cd -
rm -rf syslinux-3.86
