#!/usr/bin/env bash
#
# vpkg
#

vpkg() {
  
  # deps
  . libargue.sh || return 1
  
  # args/opts
  local tmps=()
  local opts=()
  local args=("$@")
  local cmd="$1" && shift
  local name build version
  
  # proxy to cmd
  case "$cmd" in
    "update" ) __vpkg_update "$@";;
    "lookup" ) __vpkg_lookup "$@";;
    "fetch" ) __vpkg_fetch "$@";;
    "build" ) __vpkg_build "$@";;
    "destroy" ) __vpkg_destroy "$@";;
    "link" ) __vpkg_link "$@";;
    "unlink" ) __vpkg_unlink "$@";;
    "install" ) __vpkg_install "$@";;
    "uninstall" ) __vpkg_uninstall "$@";;
    "load" ) __vpkg_load "$@";;
    "unload" ) __vpkg_unload "$@";;
    * )
      
      # parse options
      argue "-v, --version"\
            "-h, --help" || return 1

      # if we have $cmd and no options
      if [ -n "$cmd" ] && [ "${#opts[@]}" = 0 ]; then
        echo "$cmd: command not found" >&2 && return 1
      elif [ -n "${opts[0]}" ]; then
        __vpkg_version
      else
        __vpkg_usage
      fi
  esac
  
  # capture command status
  local status="$?"
  
  # clean up any temp files
  local t
  for t in "${tmps[@]}"; do
    rm -rf "$t"
  done
  
  # return proper status
  return "$status"
}

__vpkg_version() {
  echo "0.0.3"
}

__vpkg_usage() {
  echo "usage: vpkg <command> [<options>] <package> [<build>] [<version>]"
}

# public command wrappers
# -----------------------

__vpkg_update() {
  args=("$@")
  argue || return 1
  __vpkg_update__
}

__vpkg_lookup() {
  args=("$@")
  argue || return 1
  __vpkg_init__ || return 1
  __vpkg_lookup__
}

__vpkg_fetch() {
  args=("$@")
  argue "--as, +" || return 1
  local rename="${opts[0]}"
  __vpkg_init__ || return 1
  __vpkg_fetch__
}

__vpkg_build() {
  args=("$@")
  argue "--as, +"\
        "-r, --rebuild" || return 1
  local rename="${opts[0]}"
  local rebuild="${opts[1]}"
  __vpkg_init__ || return 1
  __vpkg_defaults__
  __vpkg_build__
}

__vpkg_destroy() {
  args=("$@")
  argue || return 1
  __vpkg_init__ || return 1
  __vpkg_destroy__
}

__vpkg_link() {
  args=("$@")
  argue "--as, +"\
        "-r, --rebuild" || return 1
  local rename="${opts[0]}"
  local rebuild="${opts[1]}"
  local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
  __vpkg_init__ || return 1
  __vpkg_link__
}

__vpkg_unlink() {
  args=("$@")
  argue || return 1
  local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
  __vpkg_init__ || return 1
  __vpkg_unlink__ "$build"
}

__vpkg_install() {
  args=("$@")
  argue "--as, +"\
        "-r, --rebuild" || return 1
  local rename="${opts[0]}"
  local rebuild="${opts[1]}"
  local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
  __vpkg_init__ || return 1
  __vpkg_defaults__
  __vpkg_link__
}

__vpkg_uninstall() {  
  args=("$@")
  argue "-d, --destroy"\
        "-p, --purge" || return 1
  local destroy="${opts[0]}"
  local purge="${opts[1]}"
  local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
  __vpkg_init__ || return 1
  __vpkg_defaults__
  __vpkg_uninstall__
}

__vpkg_load() {
  args=("$@")
  argue "--as, +"\
        "-r, --rebuild" || return 1
  local rename="${opts[0]}"
  local rebuild="${opts[1]}"
  __vpkg_init__ || return 1
  __vpkg_load__
}

__vpkg_unload() {
  args=("$@")
  argue || return 1
  __vpkg_init__ || return 1
  __vpkg_unload__ "$build"
}

# internal methods
# ----------------

__vpkg_init__() {
  name="${args[0]}"
  build="${args[1]}"
  version="${args[2]}"
  if [ -z "$name" ]; then
    echo "please specify a package to $cmd" >&2
    return 1
  else
    return 0
  fi
}

__vpkg_defaults__() {
  [ -z "$build" ] && build="default"
  [ -z "$version" ] && version="$build"
}

__vpkg_push_temp__() {
  tmps=("${#tmps[@]}" "$1")
}

__vpkg_run_hook__() {
  local hook="$1"
  local recipe="$VPKG_HOME"/etc/"$name"/package.sh && [ -n "$2" ] && recipe="$2"
  
  # can't run hooks unless we have a recipe
  if [ ! -e "$recipe" ]; then
    
    # the build hook is basically required.
    # if your recipe doesn't define one, we
    # need to return an error so that vpkg
    # knows to generate the build manually
    [ "$hook" = "build" ] && return 78
    return 0
  fi
  
  # run hooks in subshell for safety
  (
    # try to bail fast if things go south
    # note: beware set -e comes with caveats
    set -e
    
    # cd into the package's src dir if it exists
    [ -d "$VPKG_HOME"/src/"$name" ] && cd "$VPKG_HOME"/src/"$name"
    
    # ensure our hooks are clean or have sensible defaults
    eval "${hook}() { :; }"   # clean arbitrary hooks
    build() { return 78; }    # build is required, so it must return an error by default
    version() { :; }          # version is used every time
    
    # source the recipe
    . "$recipe"
    
    # if version = default, see if the recipe defines one
    if [ "$version" = "default" ]; then
      tmp="$(version)"
      [ -n "$tmp" ] && version="$tmp"
    fi
    
    # export handy variables for the recipe to use
    export NAME="$name"
    export BUILD="$build"
    export VERSION="$version"
    export ETC="$VPKG_HOME"/etc/"$name"
    export SRC="$VPKG_HOME"/src/"$name"
    export LIB="$VPKG_HOME"/lib/"$name"/"$build"
    
    # run hook
    "$hook"
  )
}

__vpkg_choose_package_name__() {  
  local n=0
  local original="$1"
  local default="$original"
  
  # if we are connected to a terminal we can ask for it
  if [ -t 1 ]; then
    name=""
    while [ -z "$name" ]; do
      read -a name -p "> save as [$default]: "
      [ -z "$name" ] && name="$default"
      if [ -e "$VPKG_HOME"/src/"$name" ]; then
        default="${original}_$((n++))"
        name=""
      fi
    done

  # if we don't have a terminal, just use the default
  else
    name="$default"
  fi
}

__vpkg_build_deps__() {
  local dependant="$name"
  local dep
  local name="$name"
  local build
  local version
  
  while read dep; do
    dep=($dep)
    name="${dep[0]}"
    build="${dep[1]}"
    version="$build"
    
    # echo "$dependant: building dependency: $name $build..." >&2
    __vpkg_defaults__
    __vpkg_build__
  done < <(__vpkg_run_hook__ "dependencies")
}

__vpkg_update__() {
  echo "update.private: $name: not-implemented" >&2
}

__vpkg_lookup__() {
  local registry_cache="$VPKG_HOME"/etc/vpkg
  local recipe_url
  
  # update registries if the cache is empty
  if [ ! -e "$registry_cache" ] || [ -z "$(ls -A "$registry_cache")" ]
  then
    #vpkg update &> /dev/null || {
      echo "warning: attempted to lookup $name, but no registries were found. try running"'`vpkg update`' >&2
      return 1
    #}
  fi
  
  # attempt to lookup a url for $name from your registries
  while read registry
  do
  
    # in a subshell, source the registry and do a lookup
    recipe_url="$(
      unset "$name" 2> /dev/null;
      source "$registry_cache/$registry";
      [ -n "${!name}" ] && echo "${!name}"
    )"
    
    # if we found a url, break out of the loop
    [ -n "$recipe_url" ] && break
  
  done < <(ls -A "$registry_cache")
  
  # if we didn't get a url, that's an error
  [ -z "$recipe_url" ] && echo "$name: recipe not found" >&2 && return 1
  
  # print url to stdout
  echo "$recipe_url"
}

__vpkg_fetch__() {
  local tmp
  local url
  local download
  local filetype
  
  # do not proceed if rename was specd but the source already exists
  [ -n "$rename" ] && [ -e "$VPKG_HOME"/src/"$rename" ] && echo "$rename: source exists" >&2 && return 0
  
  # already have in src?
  if [ -e "$VPKG_HOME"/src/"$name" ]; then
    
    # are we renaming?
    if [ -n "$rename" ]; then
      cp -R "$VPKG_HOME"/src/"$name" "$VPKG_HOME"/src/"$rename"
    fi
    return 0
  fi
  
  # do we have a recipe?
  if [ -e "$VPKG_HOME"/etc/"$name"/package.sh ]; then
    mkdir -p "$VPKG_HOME"/src/"$name"
    __vpkg_run_hook__ "fetch"; [ $? != 0 ] && return 1
    return 0
  fi
  
  # do we have $name in our registries?
  url="$(__vpkg_lookup__ 2> /dev/null)" || url="$name"
  
  # we should have a valid url by now
  ! curl -I "$url" &> /dev/null && echo "$url: package not registered and not a valid URL" >&2 && return 1
  
  # create a temp folder to download to
  ! tmp="$(mktemp -d "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" && echo "fetch: could not create temporary directory" >&2 && return 1
  __vpkg_push_temp__ "$tmp"
  
  # try to download file
  # do in subshell for cd
  echo "downloading $url..."
  (
    cd "$tmp"
    ! curl -fLO# "$url" && return 1
  )
  
  # what'd we get?
  download="${tmp}/$(ls -A "$tmp")"
  filetype="$(file "$download" | sed "s/.*: //")"

  # recipe?
  if echo "$filetype" | grep -q "\(shell\|bash\|zsh\).*executable"; then
    [ -n "$rename" ] && name="$rename" || name="$(__vpkg_run_hook__ "name" "$download")"
    [ -z "$name" ] && echo "$url: recipe did not provide a name, try passing one manually: "'`vpkg <command> <url> --as <name>`' && return 1
    
    # copy recipe to etc
    mkdir -p "$VPKG_HOME"/etc/"$name"
    rm -f "$VPKG_HOME"/etc/"$name"/package.sh
    cp "$download" "$VPKG_HOME"/etc/"$name"/package.sh
    
    # run fetch hook
    mkdir -p "$VPKG_HOME"/src/"$name"
    __vpkg_run_hook__ "fetch"; [ $? != 0 ] && return 1
  
  # archive? something else?
  else
    
    # tarball?
    if echo "$filetype" | grep -q "gzip compressed"; then
      ! tar -xvzf "$download" -C "$tmp" && return 1
  
    # zip archive?
    elif echo "$filetype" | grep -q "Zip archive"; then
      ! unzip "$download" -d "$tmp" && return 1
  
    # unknown
    else
      echo "fetch: unknown filetype: $filetype" >&2 && return 1 
    fi
    
    # get the name of whatever was unarchived
    rm "$download"
    download=($(ls -A "$tmp"))
    
    # rename if possible 
    if [ -n "$rename" ]; then
      name="$rename"
    
    # otherwise give the user a chance
    else
      __vpkg_choose_package_name__ "$download"
      [ -e "$VPKG_HOME"/src/"$name" ] && echo "$name: source exists" >&2 && return 1
    fi
    
    # copy over the files
    mv "$tmp"/"$download" "$VPKG_HOME"/src/"$name"
  fi
  
  # if we got here, it worked
  return 0
}

__vpkg_build__() {
  # local name="$name"
  local build="$build"
  local version="$version"
  local rename="$rename"
  local rebuild="$rebuild"
  
  __vpkg_fetch__; [ $? != 0 ] && return 1  
  __vpkg_build_deps__; [ $? != 0 ] && return 1
  
  # if --rebuild, destroy first
  if [ -n "$rebuild" ]; then
    __vpkg_destroy__; [ $? != 0 ] && return 1
  fi
  
  # already built?
  [ -e "$VPKG_HOME"/lib/"$name"/"$build" ] && return 0
  
  # mkdirs
  mkdir -p "$VPKG_HOME"/lib/"$name"
  
  # hook
  __vpkg_run_hook__ "build"
  status="$?"

  # build manually?
  if [ "$status" = 78 ]; then
    cp -R "$VPKG_HOME"/src/"$name" "$VPKG_HOME"/lib/"$name"/"$build"
  else
    return "$status"
  fi
}

__vpkg_destroy__() {
  local lib="$VPKG_HOME"/lib/"$name"
  
  __vpkg_unload__ "$build" &> /dev/null; [ $? != 0 ] && return 1
  __vpkg_unlink__ "$build" &> /dev/null; [ $? != 0 ] && return 1
  __vpkg_defaults__
  
  if [ -e "$lib"/"$build" ]; then
    __vpkg_run_hook__ "destroy"; [ $? = 0 ] || return 1
    rm -rf "$lib"/"$build"
    [ -z "$(ls -A "$lib")" ] && rm -rf "$lib"
  else
    echo "$name/$build: not built" >&2
  fi
}

__vpkg_link__() {
  local lib="$VPKG_HOME"/lib/"$name"
  local executable
  
  # is anything suitable already linked?
  if [ -n "$build" ]; then
    if [ "$link" = "$build" ]; then
      echo "$name/$build: already linked" >&2 && return 0
    fi
  else
    if [ -n "$link" ]; then
      echo "$name/$link: already linked" >&2 && return 0
    fi
  fi
  
  __vpkg_defaults__
  
  # build stuff if we need to
  if [ ! -e "$lib"/"$build" ]; then
    __vpkg_build__; [ $? != 0 ] && return 1
    __vpkg_link__
    return 0
  fi
  
  # unlink any others
  __vpkg_unlink__ &> /dev/null; [ $? = 0 ] || return 1
  
  # create link
  ln -sf "$lib"/"$build" "$lib"/current
  
  # executables
  while read executable; do
    local dest="$VPKG_HOME"/bin/"$executable"
  
    # linking happens differently depending on whether the file is executable
    if [ -x "$lib"/"$build"/bin/"$executable" ]; then
    
      # link via exec
      echo "exec ${lib}/${build}/bin/$executable "'$@' >> "$dest"
      chmod +x "$dest"
    else
    
      # soft link
      ln -sf "$lib"/"$build"/bin/"$executable" "$dest"
    fi
  done < <(ls -A "$lib"/"$build"/bin 2> /dev/null)
  
  # man pages
  if [ -d "$lib"/"$build"/share/man ]; then
    man_dest="$VPKG_HOME"/share/man
    man_source="$lib"/"$build"/share/man
    while read mangroup; do
      while read manpage; do
        mkdir -p "$man_dest"/"$mangroup"
        ln -s "$man_source"/"$manpage" "$man_dest"/"$mangroup"/
      done < <(ls -A "$man_source"/"$mangroup" 2> /dev/null)
    done < <(ls -A "$man_source" 2> /dev/null)
  fi
  
  # forget old executables
  hash -r
}

__vpkg_unlink__() {
  local build="$1"
  local lib="$VPKG_HOME"/lib/"$name"
  local executable
  
  # was a build specd?
  if [ -n "$build" ]; then
    
    # don't continue if the link doesn't match the specd build
    if [ "$link" != "$build" ]; then
      echo "$name/$build: not linked" >&2
      return 0
    fi
    
  # if nothing is linked, just return
  elif [ -z "$link" ]; then
    echo "$name: not linked" >&2
    return 0
  fi
  
  # remove link
  rm "$lib"/current
  
  # remove old executables
  while read executable; do
    rm "$VPKG_HOME"/bin/"$executable"
  done < <(ls -A "$lib"/"$link"/bin 2> /dev/null)
  
  # remove man pages
  if [ -d "$lib"/"$link"/share/man ]; then
    man_source="$lib"/"$link"/share/man
    while read mangroup; do
      while read manpage; do
        rm "$VPKG_HOME"/share/man/"$mangroup"/"$manpage"
      done < <(ls -A "$man_source"/"$mangroup" 2> /dev/null)
    done < <(ls -A "$man_source" 2> /dev/null)
  fi
  
  # forget old executables
  hash -r
}

__vpkg_uninstall__() {
  __vpkg_unload__ "$build" &> /dev/null; [ $? = 0 ] || return 1
  __vpkg_unlink__ "$build" &> /dev/null; [ $? = 0 ] || return 1
  
  # --purge? --destroy?
  if [ -n "$purge" ]; then
    __vpkg_destroy__; [ $? = 0 ] || return 1
    rm -rf "$VPKG_HOME"/{lib, etc, src, tmp}/"$name"
  elif [ -n "$destroy" ]; then
    __vpkg_destroy__
  fi
}

__vpkg_load__() {
  local lib="$VPKG_HOME"/lib/"$name"
  
  # is anything suitable already loaded?
  [ -n "$build" ] && local search="$build" || local search="[^/]*"
  if echo "$PATH" | grep -q "$lib/$search/bin"; then
    build="$(echo "$PATH" | sed "s|.*$lib/\($search\)/bin.*|\1|")"
    echo "$name/$build: already loaded" >&2 && return 0
  fi
  
  __vpkg_defaults__
  
  # build stuff if we need to
  if [ ! -e "$VPKG_HOME"/lib/"$name"/"$build" ]; then
    __vpkg_build__; [ $? != 0 ] && return 1
    __vpkg_load__
    return 0
  fi
  
  __vpkg_unload__ &> /dev/null; [ $? != 0 ] && return 1
  
  # add package/version/bin to PATH
  [ -n "$PATH" ] && PATH=":$PATH"
  export PATH="$lib"/"$build"/bin"$PATH"
}

__vpkg_unload__() {
  local build="$1"
  local lib="$VPKG_HOME"/lib/"$name"
  
  # don't unload unless loaded
  if ! echo "$PATH" | grep -q "$lib/[^/]*/bin"; then
    echo "$name: not loaded" >&2
    return 0
  elif [ -n "$build" ] && ! echo "$PATH" | grep -q "$lib/$build/bin"; then
    echo "$name/$build: not loaded" >&2
    return 1
  fi
  
  # edit PATH
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin:||g")"
  export PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin||g")"
}
