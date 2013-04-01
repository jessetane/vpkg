#
# test.sh
#

foo() {
  echo "asdf"
}

while read line; do
  echo "hey: $line"
done < <(foo)

echo "AHA: $?"

exit 1

src="/Users/jessetane/Dropbox/software/src"
rm -rf "$src"/vpkg/test/tmp
mkdir -p "$src"/vpkg/test/tmp
cd "$src"/vpkg/test/tmp
curl -fL# "file://$src"/vpkg/.vpkg | SOURCE="file://$src" bash