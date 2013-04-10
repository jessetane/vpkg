#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/liba"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

dependencies() {
  echo "libb 0.0.1"
}

build() {
  cp -R "$SRC" "$LIB"
  liba="$LIB"/bin/liba.sh
  sed "s/\$VERSION/$VERSION/" < "$liba" > "$liba"
}