#!/usr/bin/env bash
set -euo pipefail
wget https://download.virtualbox.org/virtualbox/7.2.6/VirtualBox-7.2.6.tar.bz2 
tar xvf VirtualBox-7.2.6.tar.bz
cd VirtualBox-7.2.6
patch -p1 < ../vbox_with_clang/VirtualBox-7.2.6-clang.patch
../vbox_with_clang/build-coverage.sh $PWD
patch -p1 < ../vbox_with_clang/VirtualBox-7.2.6-clang.patch -R
