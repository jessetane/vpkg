#!/usr/bin/env bash
#
# test.sh
#

# sandbox
src="/Users/jessetane/Dropbox/software/src"
rm -rf "$src"/vpkg/test/tmp
mkdir -p "$src"/vpkg/test/tmp
cd "$src"/vpkg/test/tmp

# bootstrap
curl -fL# "file://$src"/vpkg/package.sh | SOURCE="file://$src" bash
