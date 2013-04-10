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
  bin="$LIB"/bin
  sed "s/\$VERSION/$VERSION/" < "$bin"/liba.sh > "$bin"/tmp
  mv "$bin"/tmp "$bin"/liba.sh
}
