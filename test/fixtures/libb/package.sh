#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/libb"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

build() {
  echo 'libb() { echo "libb: $VERSION"; }' > "$SRC"/bin/libb.sh
  return 78
}