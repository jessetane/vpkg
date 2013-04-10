#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/binb"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

build() {
  mkdir -p "$LIB"/bin
  echo "echo \"binb: $VERSION\"" > "$LIB"/bin/binb
  chmod +x "$LIB"/bin/binb
}
