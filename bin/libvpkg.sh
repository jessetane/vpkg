#!/usr/bin/env bash
#
# vpkg
#

vpkg() {
  
  # deps
  . libargue.sh || return 1
  
  # args/opts
  local argv=("$@")
  local opts=()
  local tmps=()
  local cmd="$1" && shift
  local args=("$@")
  local name build version
  
  # proxy to cmd
  case "$cmd" in
    
    "update" )
      argue || return 1
      __vpkg_update
      
    ;; "lookup" )
      argue || return 1
      __vpkg_init || return 1
      __vpkg_lookup
    
    ;; "fetch" )
      argue "--as, +" || return 1
      local rename="${opts[0]}"
      __vpkg_init || return 1
      __vpkg_fetch
    
    ;; "build" )
      argue "--as, +"\
            "-r, --rebuild" || return 1
      local rename="${opts[0]}"
      local rebuild="${opts[1]}"
      __vpkg_init || return 1
      __vpkg_defaults
      __vpkg_build
    
    ;; "destroy" )
      argue || return 1
      __vpkg_init || return 1
      __vpkg_destroy
    
    ;; "link" )
      argue "--as, +"\
            "-r, --rebuild" || return 1
      local rename="${opts[0]}"
      local rebuild="${opts[1]}"
      local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
      __vpkg_init || return 1
      __vpkg_link
    
    ;; "unlink" )
      argue || return 1
      local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
      __vpkg_init || return 1
      __vpkg_unlink "$build"
    
    ;; "install" )
      argue "--as, +"\
            "-r, --rebuild" || return 1
      local rename="${opts[0]}"
      local rebuild="${opts[1]}"
      local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
      __vpkg_init || return 1
      __vpkg_defaults
      __vpkg_link
    
    ;; "uninstall" )
      argue "-d, --destroy"\
            "-p, --purge" || return 1
      local destroy="${opts[0]}"
      local purge="${opts[1]}"
      local link="$(basename "$(readlink "$VPKG_HOME"/lib/"${args[0]}"/current)")"
      __vpkg_init || return 1
      __vpkg_uninstall
    
    ;; "load" )
      argue "--as, +"\
            "-r, --rebuild" || return 1
      local rename="${opts[0]}"
      local rebuild="${opts[1]}"
      __vpkg_init || return 1
      __vpkg_load

    ;; "unload" )
      argue || return 1
      __vpkg_init || return 1
      __vpkg_unload "$build"
    
    ;; * )
      
      # parse options
      args=("${argv[@]}")
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

__vpkg_init() {
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

__vpkg_defaults() {
  [ -z "$build" ] && build="default"
  [ -z "$version" ] && version="$build"
  return 0
}

__vpkg_push_temp() {
  tmps=("${#tmps[@]}" "$1")
}

__vpkg_package_exists() {
  test -e "$VPKG_HOME"/etc/"$name"/package.sh
}

__vpkg_choose_package_name() {  
  local n=0
  local original="$1"
  local default="$original"
  
  # if we are connected to a terminal we can ask for it
  if [ -t 1 ]; then
    name=""
    while [ -z "$name" ]; do
      read -a name -p "> save as [$default]: "
      [ -z "$name" ] && name="$default"
      if __vpkg_package_exists; then
        default="${original}_$((n++))"
        name=""
      fi
    done

  # if we don't have a terminal, just use the default
  else
    name="$default"
  fi
}

__vpkg_update() {
  echo "update.private: $name: not-implemented" >&2
}

__vpkg_lookup() {
  local registry_cache="$VPKG_HOME"/etc/vpkg
  local recipe_url
  
  # update registries if the cache is empty
  if [ ! -e "$registry_cache" ] || [ -z "$(ls -A "$registry_cache")" ]; then
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

__vpkg_run_hook() {
  local hook="$1"
  local recipe="$VPKG_HOME"/etc/"$name"/package.sh && [ -n "$2" ] && recipe="$2"
  
  # can't run hooks unless we have a recipe
  if [ ! -e "$recipe" ]; then
    
    # the build hook is basically required.
    # if your recipe doesn't define one, we
    # need to remove a flag so that vpkg
    # knows to generate the build manually
    [ "$hook" = "build" ] && rm "$build_flag"
    return 0
  fi
  
  # run hooks in subshell for safety
  (
    # try to bail fast if things go south
    # beware: set -e comes with caveats
    set -e
    
    # cd into the package's src dir if it exists
    [ -d "$VPKG_HOME"/src/"$name" ] && cd "$VPKG_HOME"/src/"$name"
    
    # ensure our hooks are clean or have sensible defaults
    eval "${hook}() { :; }"         # clean arbitrary hooks
    build() { rm "$build_flag"; }   # build is required, so it must clear a flag by default
    version() { :; }                # version is used every time
    
    # source the recipe
    . "$recipe"
    
    # if version = default, see if the recipe defines one
    if [ "$version" = "default" ]; then
      tmp="$(version)"
      [ -n "$tmp" ] && version="$tmp"
    fi
    
    # handy environment variables for the recipe to use
    NAME="$name"
    BUILD="$build"
    VERSION="$version"
    ETC="$VPKG_HOME"/etc/"$name"
    SRC="$VPKG_HOME"/src/"$name"
    LIB="$VPKG_HOME"/lib/"$name"/"$build"
    
    # run hook
    "$hook"
  )
}

__vpkg_fetch_url() {
  local tmp
  
  # url is valid?
  ! curl -Ifso /dev/null -w "%{http_code}" "$url" | grep -q "^\(2\|3\)" && echo "$url: not a valid URL" >&2 && return 1
  
  # create a temp folder to download to
  ! tmp="$(mktemp -d "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" && echo "fetch: could not create temporary directory" >&2 && return 1
  __vpkg_push_temp "$tmp"
  
  # attempt download in subshell so we can cd into tmp
  echo "downloading $url..."
  (
    cd "$tmp"
    ! curl -fLO# "$url" && return 1
  )
  
  # what'd we get?
  download="${tmp}/$(ls -A "$tmp")"
  filetype="$(file "$download" | sed "s/[^:]*: //")"
  
  # recipe?
  if echo "$filetype" | grep -q "\(shell\|bash\|zsh\).*executable"; then
    filetype="recipe"
  
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
      echo "fetch: unknown filetype: $(file "$download")" >&2 && return 1
    fi
    
    # get the name of whatever was unarchived
    rm "$download"
    download=($(ls -A "$tmp"))
    filetype="source"
  fi
}

__vpkg_fetch() {
  local url
  local original="$name"
  local package_sh="$VPKG_HOME"/etc/"$name"/package.sh
  local download
  local filetype
  
  # are we missing package.sh?
  if ! __vpkg_package_exists; then
    
    # get a url any way we can
    url="$(__vpkg_lookup 2> /dev/null)" 
    
    # did we get a url?
    if [ -z "$url" ]; then
      
      # if we couldn't do a lookup, but we have source code, that's OK
      if [ -e "$VPKG_HOME"/src/"$name" ]; then
        package_sh="$VPKG_HOME"/etc/"$name"/package.sh
        mkdir -p "$VPKG_HOME"/etc/"$name"
        touch "$package_sh"
        return 0
      fi
      url="$name"
    fi
    
    # fetch it
    __vpkg_fetch_url; [ $? != 0 ] && return 1
    
    # did we get a recipe
    if [ "$filetype" = "recipe" ]; then
      
      # try to rename via --as or package.sh name
      [ -n "$rename" ] && name="$rename" || name="$(__vpkg_run_hook "name" "$download")"
      [ -z "$name" ] && echo "$url: package.sh did not provide a name, try passing one manually with --as <name>" && return 1
    
      # bail if the package already exists
      __vpkg_package_exists && echo "$name: package exists" >&2 && return 1
      
      # copy over the download package.sh
      package_sh="$VPKG_HOME"/etc/"$name"/package.sh
      mkdir -p "$VPKG_HOME"/etc/"$name"
      mv "$download" "$package_sh"
    
    # we got raw source code
    else
      
      # try to rename
      if [ -n "$rename" ]; then
        name="$rename"
      else
        __vpkg_choose_package_name "$download"
      fi
      
      # bail if the package already exists
      __vpkg_package_exists && echo "$name: pacakge exists" >&2 && return 1
      
      # generate package.sh
      package_sh="$VPKG_HOME"/etc/"$name"/package.sh
      mkdir -p "$VPKG_HOME"/etc/"$name"
      if [ -e "$tmp"/"$download"/package.sh ]; then
        cp "$tmp"/"$download"/package.sh "$package_sh"
      else
        touch "$package_sh"
      fi
      
      # copy over the source
      mv "$tmp"/"$download" "$VPKG_HOME"/src/"$name"
    fi
    
  # so we have pkg.sh, but was the user trying to rename?
  elif [ -n "$rename" ]; then
    name="$rename"
    
    # bail if the package already exists
    __vpkg_package_exists && echo "$name: pacakge exists" >&2 && return 1
    
    # copy over the package.sh
    package_sh="$VPKG_HOME"/etc/"$name"/package.sh
    mkdir -p "$VPKG_HOME"/etc/"$name"
    cp "$VPKG_HOME"/etc/"$original"/package.sh "$package_sh"
  fi
  
  # try the fetch hook if we don't have source code
  if [ ! -e "$VPKG_HOME"/src/"$name" ]; then
    __vpkg_run_hook "fetch"; [ $? != 0 ] && return 1
    
    # hmm, we STILL don't have source code...
    if [ ! -e "$VPKG_HOME"/src/"$name" ]; then

      # if we changed names, try copying it over manually
      if [ "$original" != "$name" ]; then
        cp -R "$VPKG_HOME"/src/"$original" "$VPKG_HOME"/src/"$name"
      else
        echo "$name: source could not be fetched" >&2 && return 1
      fi
    fi
  fi
}

__vpkg_build_deps() {
  local dependant="$name"
  local dep
  local name="$name"
  local build
  local version
  local rename
  
  while read dep; do
    dep=($dep)
    name="${dep[0]}"
    build="${dep[1]}"
    version="$build"
    
    echo "$dependant: building dependency: $name $build..." >&2
    __vpkg_defaults
    __vpkg_build
  done < <(__vpkg_run_hook "dependencies")
}

__vpkg_build() {
  local build="$build"
  local version="$version"
  local rename="$rename"
  local rebuild="$rebuild"
  local build_flag
  
  # if --rebuild, destroy first
  if [ -n "$rebuild" ]; then
    __vpkg_destroy; [ $? != 0 ] && return 1
  fi
  
  # already built?
  [ -e "$VPKG_HOME"/lib/"$name"/"$build" ] && return 0
  
  # get recipes/deps/source
  __vpkg_fetch; [ $? != 0 ] && return 1
  __vpkg_build_deps; [ $? != 0 ] && return 1
  
  # mkdirs
  mkdir -p "$VPKG_HOME"/lib/"$name"
  
  # hook
  ! build_flag="$(mktemp "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" && echo "fetch: could not create temporary file" >&2 && return 1
  __vpkg_push_temp "$build_flag"
  __vpkg_run_hook "build"; [ $? != 0 ] && return 1
  
  # build manually?
  if [ ! -e "$build_flag" ]; then
    cp -R "$VPKG_HOME"/src/"$name" "$VPKG_HOME"/lib/"$name"/"$build"
  fi
  
  # wrap
  __vpkg_wrap
}

__vpkg_wrap() {
  local lib="$VPKG_HOME"/lib/"$name"
  local sbin="$VPKG_HOME"/sbin/"$name"/"$build"
  local dep deps dep_name dep_build dest
  
  # build loader
  while read dep; do
    dep=($dep)
    dep_name="${dep[0]}"
    dep_build="${dep[1]}"
    deps="$deps\nvpkg load $dep_name $dep_build"
  done < <(__vpkg_run_hook "dependencies")
  
  # only source the vpkg lib if we need it
  [ -n "$deps" ] && deps=". libvpkg.sh${deps}\n"
  
  # generate wrappers
  while read executable; do
    mkdir -p "$sbin"
    dest="$sbin"/"$executable"
    
    # executables get exec'd
    if [ -x "$lib"/"$build"/bin/"$executable" ]; then
      echo -e "${deps}exec ${lib}/${build}/bin/$executable "'"$@"' >> "$dest"
      chmod +x "$dest"
    
    # sourceable shell scripts get sourced
    elif echo "$executable" | egrep -q "\.sh$"; then
      echo -e "${deps}source ${lib}/${build}/bin/$executable "'"$@"' >> "$dest"
    
    # unknown file types get soft linked
    else
      ln -sf "$lib"/"$build"/bin/"$executable" "$dest"
    fi
  done < <(ls -A "$lib"/"$build"/bin 2> /dev/null)
  
  # if we got here, it worked
  return 0
}

__vpkg_unwrap() {
  local sbin="$VPKG_HOME"/sbin/"$name"
  rm -rf "$sbin"/"$build"
  [ -z "$(ls -A "$sbin" 2> /dev/null)" ] && rm -rf "$sbin"
}

__vpkg_destroy() {
  local lib="$VPKG_HOME"/lib/"$name"
  local build="$build"
  local builds 
  
  if [ -n "$build" ]; then
    [ ! -e "$lib"/"$build" ] && echo "$name/$build: not built" >&2 && return 0
    builds=("$build")
  else
    builds=($(ls -A "$lib" 2> /dev/null))
  fi
  
  for build in "${builds[@]}"; do
    __vpkg_unload "$build" &> /dev/null; [ $? != 0 ] && return 1
    __vpkg_unlink "$build" &> /dev/null; [ $? != 0 ] && return 1
    __vpkg_run_hook "destroy"; [ $? = 0 ] || return 1
    __vpkg_unwrap
    rm -rf "$lib"/"$build"
  done
  
  # last one out turn out the light
  [ -z "$(ls -A "$lib" 2> /dev/null)" ] && rm -rf "$lib"
  
  # if we got here it worked
  return 0
}

__vpkg_link() {
  local lib="$VPKG_HOME"/lib/"$name"
  local sbin="$VPKG_HOME"/sbin/"$name"
  local executable mangroup manpage
  
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
  
  __vpkg_defaults
  
  # build stuff if we need to
  if [ ! -e "$lib"/"$build" ]; then
    __vpkg_build; [ $? != 0 ] && return 1
    __vpkg_link; return $?
  fi
  
  # unlink any others
  __vpkg_unlink &> /dev/null; [ $? = 0 ] || return 1
  
  # create link
  ln -sf "$lib"/"$build" "$lib"/current
  
  # executables
  while read executable; do
    local dest="$VPKG_HOME"/bin/"$executable"
  
    # linking happens differently depending on whether the file is executable
    if [ -x "$sbin"/"$build"/"$executable" ]; then
    
      # link via exec
      echo "exec ${sbin}/${build}/$executable "'"$@"' >> "$dest"
      chmod +x "$dest"
    else
    
      # soft link
      ln -sf "$sbin"/"$build"/"$executable" "$dest"
    fi
  done < <(ls -A "$lib"/"$build"/bin 2> /dev/null)
  
  # man pages
  if [ -d "$lib"/"$build"/share/man ]; then
    local man_dest="$VPKG_HOME"/share/man
    local man_source="$lib"/"$build"/share/man
    while read mangroup; do
      while read manpage; do
        mkdir -p "$man_dest"/"$mangroup"
        ln -s "$man_source"/"$mangroup"/"$manpage" "$man_dest"/"$mangroup"/
      done < <(ls -A "$man_source"/"$mangroup" 2> /dev/null)
    done < <(ls -A "$man_source" 2> /dev/null)
  fi
  
  # forget old executables
  hash -r
}

__vpkg_unlink() {
  local build="$1"
  local lib="$VPKG_HOME"/lib/"$name"
  local executable mangroup manpage
  
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
    local man_source="$lib"/"$link"/share/man
    while read mangroup; do
      while read manpage; do
        rm "$VPKG_HOME"/share/man/"$mangroup"/"$manpage"
      done < <(ls -A "$man_source"/"$mangroup" 2> /dev/null)
    done < <(ls -A "$man_source" 2> /dev/null)
  fi
  
  # forget old executables
  hash -r
}

__vpkg_uninstall() {
  __vpkg_unload "$build" &> /dev/null; [ $? = 0 ] || return 1
  __vpkg_unlink "$build" &> /dev/null; [ $? = 0 ] || return 1
  
  # --purge? --destroy?
  if [ -n "$purge" ]; then
    __vpkg_destroy; [ $? = 0 ] || return 1
    rm -rf "$VPKG_HOME"/{etc,sbin,lib,src,tmp}/"$name"
  elif [ -n "$destroy" ]; then
    __vpkg_destroy
  fi
}

__vpkg_load() {
  local lib="$VPKG_HOME"/lib/"$name"
  local sbin="$VPKG_HOME"/sbin/"$name"
  
  # is anything suitable already loaded?
  [ -n "$build" ] && local search="$build" || local search="[^/]*"
  if echo "$PATH" | grep -q "$sbin/$search"; then
    build="$(echo "$PATH" | sed "s|.*$sbin/\($search\).*|\1|")"
    echo "$name/$build: already loaded" >&2 && return 0
  fi
  
  __vpkg_defaults
  
  # build stuff if we need to
  if [ ! -e "$lib"/"$build" ]; then
    __vpkg_build; [ $? != 0 ] && return 1
    __vpkg_load; return $?
  fi
  
  __vpkg_unload &> /dev/null; [ $? != 0 ] && return 1
  
  # add package/version/bin to PATH
  [ -n "$PATH" ] && PATH=":$PATH"
  PATH="$sbin"/"${build}${PATH}"
}

__vpkg_unload() {
  local build="$1"
  local sbin="$VPKG_HOME"/sbin/"$name"
  
  # don't unload unless loaded
  if ! echo "$PATH" | grep -q "$sbin/[^/]*"; then
    echo "$name: not loaded" >&2
    return 0
  elif [ -n "$build" ] && ! echo "$PATH" | grep -q "$sbin/$build"; then
    echo "$name/$build: not loaded" >&2
    return 1
  fi
  
  # edit PATH
  PATH="$(echo "$PATH" | sed "s|$sbin/[^/]*:||g")"
  PATH="$(echo "$PATH" | sed "s|$sbin/[^/]*||g")"
}
