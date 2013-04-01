#
# test.sh
#

src="/Users/jessetane/Dropbox/software/src"
rm -rf "$src"/vpkg/test/tmp
mkdir -p "$src"/vpkg/test/tmp
cd "$src"/vpkg/test/tmp
curl -fL# "file://$src"/vpkg/.vpkg | SOURCE="file://$src" bash

# 
cp -R "$src"/vpkg/test/fixtures/* ./src/
cd "$src"/vpkg/test/tmp
. .vpkgrc
vpkg build lib1 0.0.1
vpkg build lib1 0.0.2
vpkg build prgm1
vpkg build prgm2
vpkg build main
