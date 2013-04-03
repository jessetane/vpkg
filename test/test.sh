#!/usr/bin/env bash
#
# test.sh
#

#set -x

# sandbox
src="/Users/jessetane/Dropbox/software/src"
rm -rf "$src"/spm/test/tmp
mkdir -p "$src"/spm/test/tmp
cd "$src"/spm/test/tmp

# bootstrap
curl -fL# "file://$src"/spm/package.sh | SOURCE="file://$src" bash

# fixtures
cp -R "$src"/spm/test/fixtures/* ./src/
cd "$src"/spm/test/tmp
. .spmrc
spm build lib1 0.0.1
spm build lib1 0.0.2
spm build prgm1
spm build prgm2
spm build main
