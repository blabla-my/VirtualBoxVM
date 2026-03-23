#!/usr/bin/env bash
set -euo pipefail

cd VirtualBox-7.2.6
patch -p1 < ../vbox_with_clang/VirtualBox-7.2.6-clang.patch
../vbox_with_clang/build-coverage.sh $PWD
patch -p1 < ../vbox_with_clang/VirtualBox-7.2.6-clang.patch -R
