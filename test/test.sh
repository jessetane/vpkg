src="/Users/jessetane/Dropbox/software/src/vpkg"
rm -rf "$src"/test/tmp
mkdir -p "$src"/test/tmp
curl "file://$src"/.vpkg | bash