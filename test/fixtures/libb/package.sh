#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/libb"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

build() {
  mkdir -p "$LIB"/bin
  echo "libb() { echo \"libb: $VERSION\"; }" > "$LIB"/bin/libb.sh
}
