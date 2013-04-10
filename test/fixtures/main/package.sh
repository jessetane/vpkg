#!/usr/bin/env bash

repository() {
  echo "/Users/jessetane/Dropbox/software/src/vpkg/test/fixtures/main"
}

fetch() {
  cp -R "$(repository)" "$SRC"
}

dependencies() {
  echo "liba 0.0.1"
  echo "libb 0.0.2"
  echo "bina 0.0.1"
  echo "binb 0.0.2"
}
