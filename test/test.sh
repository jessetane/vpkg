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

# fixtures
# cp -R "$src"/spm/test/fixtures/* ./src/
# cd "$src"/spm/test/tmp
# . .spmrc
# spm build lib1 0.0.1
# spm build lib1 0.0.2
# spm build prgm1
# spm build prgm2
# spm build main
