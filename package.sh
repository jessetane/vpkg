#!/usr/bin/env bash
#
# package.sh
#

name() {
  echo "vpkg"
}

version() {
  echo "dev"
}

repository() {
  echo "https://github.com/jessetane/vpkg"
}

update() {
  cd "$SRC"
  git fetch --all
  git fetch --tags
}

build() {
  mkdir -p "$LIB"
  cp -R "$SRC"/.git "$LIB"
  cd "$LIB"
  git reset --hard "$VERSION"
}

bootstrap() {
  
  # vars
  [ -z "$SOURCE" ] && SOURCE="https://github.com/jessetane"
  VPKG_HOME="$(pwd)"
  name="vpkg"
  build="default"
  version="$(version)"
  
  # sanity
  # [ -n "$(ls -A "$VPKG_HOME")" ] && echo "$VPKG_HOME: directory is not empty" >&2 && return 1
  
  # make some dirs
  mkdir -p "$VPKG_HOME"/src/"$name"
  mkdir -p "$VPKG_HOME"/share/man
  mkdir -p "$VPKG_HOME"/etc/vpkg
  mkdir -p "$VPKG_HOME"/tmp
  mkdir -p "$VPKG_HOME"/bin
  mkdir -p "$VPKG_HOME"/sbin
  cd "$VPKG_HOME"/src/"$name"
  
  # autogenerate a sourceable profile
  # file and put it in vpkg_HOME
  profile > "$VPKG_HOME"/.vpkgrc
  
  # install dependency: argue
  git clone "$SOURCE/argue" "$VPKG_HOME"/src/argue
  ln -s "$VPKG_HOME"/src/argue/bin/libargue.sh "$VPKG_HOME"/bin/
  
  # install self
  git clone "$SOURCE/vpkg" "$VPKG_HOME"/src/vpkg
  git checkout "$version" &> /dev/null
  ln -s "$VPKG_HOME"/src/vpkg/bin/libvpkg.sh "$VPKG_HOME"/bin/
  
  # source profile
  . "$VPKG_HOME"/.vpkgrc
  
  # now we are self hosted, so do proper installation
  vpkg install argue
  vpkg install vpkg
}

profile() {
  echo -n '#
# .vpkgrc - source this
#

# vpkg root
export VPKG_HOME="'"$VPKG_HOME"'"

# add bin to PATH
export PATH="$VPKG_HOME"/bin:"$PATH"

# source vpkg command
. libvpkg.sh
'
}

# bootstrap?
[ -z "$BASH_SOURCE" ] && bootstrap
