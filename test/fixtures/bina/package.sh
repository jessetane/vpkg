#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/bina"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

dependencies() {
  echo "binb 0.0.1"
}

build() {
  cp -R "$SRC" "$LIB"
  bin="$LIB"/bin
  sed "s/\$VERSION/$VERSION/" < "$bin"/bina > "$bin"/tmp
  mv "$bin"/tmp "$bin"/bina
  chmod +x "$bin"/bina
}
