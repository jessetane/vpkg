#
# test.sh
#

src="/Users/jessetane/Dropbox/software/src"
rm -rf "$src"/vpkg/test/tmp
mkdir -p "$src"/vpkg/test/tmp
cd "$src"/vpkg/test/tmp
curl -fL# "file://$src"/vpkg/.vpkg | SOURCE="file://$src" bash
cp -R "$src"/vpkg/test/fixtures/* ./src/