#!/usr/bin/env bash
#
# libvpkg.sh
#


# internal methods

_vpkg_init_private() {
  
  # internal vars
  link_name="current"
  registry_cache="$VPKG_HOME"/etc/vpkg
}

_vpkg_init_common() {
  
  # positional args
  export cmd
  export name="${args[0]}"
  export build="${args[1]}"
  export version="${args[2]}"
  
  # dir ref shortcuts
  export etc="$VPKG_HOME"/etc/"$name"
  export bin="$VPKG_HOME"/bin/"$name"
  export lib="$VPKG_HOME"/lib/"$name"
  export src="$VPKG_HOME"/src/"$name"
  
  # require $name
  if [ -z "$name" ]
  then
    echo "please specify a package" >&2
    return 1
  else
    return 0
  fi
}

_vpkg_init_defaults() {
  [ -z "$build" ] && export build="default"
  [ -z "$version" ] && export version="$build"
}

_vpkg_hook() {
  local opts=()
  local args=("$@")
  argue "-r, --recipe, +"
  local hook="${args[0]}"
  local recipe="$etc"/.vpkg && [ -n "${opts[0]}" ] && recipe="${opts[0]}"
  
  # make sure $1 is safe for eval
  [ -z "$hook" ] && echo "vpkg: hook not specified" >&2 && return 1
  
  # run in subshell for safety
  ( 
    # try to bail fast if things go south
    # note: beware set -e, there are caveats
    set -e
    
    # makes recipes a bit more magical.. is this good?
    [ -d "$src" ] && cd "$src"
    
    # ensure our hooks are clean or have sensible defaults
    eval "${hook}() { :; }"
    version() { :; }
    build() { return 78; }
    
    # source recipe if we have one
    [ -e "$recipe" ] && . "$recipe"
    
    # if version = default, see if the recipe defines one
    if [ "$version" = "default" ]; then
      temp="$(version)" && version="$temp"
    fi
    
    # run hook
    "$hook"
  )
}

_vpkg_import_name() {
  name="$(cat "$VPKG_MASTER_INTERCOM")"
  args[0]="$name"
  _vpkg_init_common
  _vpkg_init_defaults
}

_vpkg_export_name() {
  echo "$name" > "$VPKG_MASTER_INTERCOM"
}

_vpkg_source_exists() {
  [ -e "$VPKG_HOME"/src/"$name" ] && echo "$name: source exists" >&2 && return 0
}

_vpkg_fetch_manually() {
  rm "$download"
  download="$(ls -A)"
  
  # we need a name to install the source as
  if [ "$name" = "$url" ]; then
    
    # if we are connected to a terminal we can ask for it
    if [ -t 1 ]; then
      n=0
      name=""
      default="$download"
      while [ -z "$name" ]; do
        read -a name -p "> save as [$default]: "
        [ -z "$name" ] && name="$default"
        if _vpkg_source_exists; then
          default="${download}_$((n++))"
          name=""
        fi
      done
    
    # if we don't have a terminal, just try the default
    else
      name="$download"
    fi
  fi
  
  # bail if existing
  _vpkg_source_exists && return 1
  
  # install the source
  mv "$download" "$VPKG_HOME"/src/"$name"
}

_vpkg_fail() {
  [ -n "$1" ] && echo "$1" >&2
  rm -rf "$tmp"
  return 0
}

_vpkg_build_dependencies() {
  local dep
  while read dep; do
    [ -z "$dep" ] && continue
    dep=($dep)
    local dep_name="${dep[0]}"
    local dep_version="${dep[1]}"
    [ -n "$dep_version" ] && dep="$dep_name"/"$dep_version"
    echo "$name: building dependency: $dep..." >&2
    vpkg build "$dep_name" "$dep_version"
    local status="$?"
    echo "$name: done building dependency, status was: $status"
    if [ "$status" != 0 ]; then
      echo "$name: failed to build dependency: $dep" >&2
      return "$status"
    fi
  done < <(_vpkg_hook "dependencies")
  
  # ensure the proper name is passed back up
  _vpkg_export_name
  
  # if we got here it worked
  return 0
}


# public methods

vpkg_version() {
  echo "0.0.1"
}

vpkg_usage() {
  echo "usage: vpkg <command> [<options>] <package> [<build>] [<version>]"
}

vpkg_update() {
  args=("$@")
  argue || return 1
  package="${args[0]}"
  registries="$VPKG_REGISTRIES"
  i=0
  
  # sanity
  [ -z "$registries" ] && echo "VPKG_REGISTRIES is not defined" >&2 && return 1
  
  # make sure self/etc and our tmp download dir exist
  mkdir -p "$registry_cache"/tmp
  
  # loop over registry urls
  while read registry
  do
    
    # download your registries and cache them in self/etc/registries
    # ensure ordering is respected by renaming the files
    curl -fL# "$registry" -o "$registry_cache"/tmp/"$((i++)).registry"
    
    # don't continue if there was an error
    if [ $? != 0 ]
    then
      error=true
      break
    fi
  
  done < <(echo "$registries")
  
  # if there were no errors, blow away old
  # registries and copy over the new ones
  if [ "$error" != true ]
  then
    rm -f "$registry_cache"/*.registry
    cp "$registry_cache"/tmp/* "$registry_cache"/
  fi
  
  # blow away our download dir
  rm -rf "$registry_cache"/tmp
}

vpkg_lookup() {
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1
  
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

vpkg_fetch() {
  args=("$@")
  argue "-n, --name, +" || return 1
  url="${args[0]}"
  name="${opts[0]}"
  [ -z "$name" ] && name="$url"
  
  # do we already have source code?
  while read package; do
    if [ "$package" = "$url" ]; then
      if [ "$name" != "$url" ]; then
        _vpkg_source_exists && return 1
        cp -R "$VPKG_HOME"/src/"$url" "$VPKG_HOME"/src/"$name"
      fi
      _vpkg_export_name && return 0
    fi
  done < <(ls -A "$VPKG_HOME"/src)
  
  # do we have a recipe?
  [ -e "$VPKG_HOME"/etc/"$url"/.vpkg ] && name="$url" && _vpkg_export_name && return 0
  
  # we don't have a recipe or source code yet so try 
  # to lookup the package from one of the registries
  lookup="$(vpkg lookup "$url" 2> /dev/null)" && url="$lookup"
  
  # create a temp folder to download to
  ! tmp="$(mktemp -d "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" && echo "fetch: could not create temporary directory" >&2 && return 1
  cd "$tmp"
  
  # valid url?
  ! curl -I "$url" &> /dev/null && _vpkg_fail "$url: package not registered and does not appear to be valid URL" && return 1
  
  # try to download file
  echo "downloading $url..."
  ! curl -fLO# "$url" && _vpkg_fail && return 1
  
  # what'd we get?
  download="$(pwd)/$(ls -A)"
  filetype="$(file "$download" | sed "s/.*: //")"

  # recipe?
  if echo "$filetype" | grep -q "\(shell\|bash\|zsh\).*executable"; then
    [ "$name" = "$url" ] && name="$(_vpkg_hook "name" --recipe "$download")"
    [ -z "$name" ] && _vpkg_fail "$url: recipe did not provide a name, pass one manually with --name" && return 1
    
    # copy recipe to etc
    mkdir -p "$VPKG_HOME"/etc/"$name"
    rm -f "$VPKG_HOME"/etc/"$name"/.vpkg
    cp "$download" "$VPKG_HOME"/etc/"$name"/.vpkg
    
    # run fetch hook
    _vpkg_export_name
    _vpkg_import_name
    _vpkg_source_exists || {
      mkdir -p "$src"
      _vpkg_hook "fetch"; [ $? != 0 ] && return 1
    }
  
  # tarball?
  elif echo "$filetype" | grep -q "gzip compressed"; then
    ! tar -xvzf "$download" && _vpkg_fail && return 1
    _vpkg_fetch_manually || return 1
  
  # zip archive?
  elif echo "$filetype" | grep -q "Zip archive"; then
    ! unzip "$download" && _vpkg_fail && return 1
    _vpkg_fetch_manually || return 1
  
  # unknown
  else
    _vpkg_fail "fetch: unknown filetype: $filetype" && return 1 
  fi
  
  # tell the master about any name changes
  _vpkg_export_name
  
  # remove tmp download dir
  rm -rf "$tmp"
  
  # if we got here, it worked
  return 0
}

# vpkg build [<options>] <package|url> [<build>] [<version>]
vpkg_build() {
  args=("$@")
  argue "-n, --name, +"\
        "-r, --rebuild" || return 1
  rename="${opts[0]}"
  rebuild="${opts[1]}"
  
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # bail if --name and source exists
  [ -n "$rename" ] && 
  [ -e "$VPKG_HOME"/src/"$rename" ] && echo "$rename: source exists" >&2 && return 1
  
  # get source or recipe
  vpkg fetch "$name" --name "$rename"; [ $? = 0 ] || return 1
  
  # name may have changed
  _vpkg_import_name
  
  # destroy first if --rebuild
  if [ -n "$rebuild" ]; then
    vpkg destroy "$name" "$build"; [ $? = 0 ] || return 1
  fi

  # try to build deps
  _vpkg_build_dependencies; [ $? != 0 ] && return 1
  
  # only build the package itself if we have to
  if [ ! -e "$lib"/"$build" ]; then
    mkdir -p "$lib"
    _vpkg_hook "pre_build"; [ $? = 0 ] || return 1
    
    # if the build hook is not defined, hooking it will return 78
    # indicating that we should try to copy over the files manually
    _vpkg_hook "build"
    status="$?"
    if [ "$status" = 78 ]; then
      cp -R "$src" "$lib"/"$build"
    elif [ "$status" != 0 ]; then
      return 1
    fi
    
    _vpkg_hook "post_build"; [ $? = 0 ] || return 1
  fi
  
  # if we get here it worked
  return 0
}

# vpkg destroy <package> [<build>]
vpkg_destroy() {
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # 
  vpkg unload "$@" &> /dev/null; [ $? = 0 ] || return 1
  vpkg unlink "$@" &> /dev/null; [ $? = 0 ] || return 1
  
  if [ -e "$lib"/"$build" ]; then
    _vpkg_hook "pre_destroy"; [ $? = 0 ] || return 1
    rm -rf "$lib"/"$build"
    [ -z "$(ls -A "$lib")" ] && rm -rf "$lib"
    _vpkg_hook "post_destroy"; [ $? = 0 ] || return 1
  else
    echo "$name/$build: not built" >&2
  fi
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg link <package> [<build>]
vpkg_link() {
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1

  # is anything suitable already linked?
  link="$(basename "$(readlink "$lib"/"$link_name")")"
  if [ -n "$build" ]; then
    if [ "$build" = "$link" ]; then
      echo "$name/$build: already linked" >&2 && return 0
    fi
  else
    if [ -e "$lib"/"$link_name" ]; then
      echo "$name/$link: already linked" >&2 && return 0
    fi
  fi
  
  # defaults
  _vpkg_init_defaults
  
  # bail if not built
  [ ! -e "$lib"/"$build" ] && echo "$name/$build: has not been built" >&2 && return 1
  
  # unlink any others and build if necessary
  vpkg unlink "$name" &> /dev/null; [ $? = 0 ] || return 1
  
  # event
  _vpkg_hook "pre_link"; [ $? = 0 ] || return 1
  
  # create link
  ln -sf "$lib"/"$build" "$lib"/"$link_name"
  
  # create executables
  ls -A "$lib"/"$build"/bin 2> /dev/null | while read executable; do
    local dest="$VPKG_HOME"/bin/"$executable"
  
    # linking happens differently depending on whether the file is executable
    if [ -x "$lib"/"$build"/bin/"$executable" ]; then
    
      # link via exec
      echo "export PATH=${VPKG_HOME}/bin:\$PATH" > "$dest"
      echo "exec ${lib}/${build}/bin/$executable "'$@' >> "$dest"
      chmod +x "$dest"
    else
    
      # soft link
      ln -sf "$lib"/"$build"/bin/"$executable" "$dest"
    fi
  done

  # event
  _vpkg_hook "post_link"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg unlink <package> [<build>]
vpkg_unlink() {
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1
  
  # follow the current link or just return if no builds are linked
  old_link="$(readlink "$lib"/"$link_name")"
  
  # don't unlink unless actually linked
  if [ -z "$old_link" ] || [[ -n "$build" && "$old_link" != "$lib"/"$build" ]]; then
    _vpkg_init_defaults
    echo "$name/$build: not linked" >&2
    return 0
  fi
  
  # event
  _vpkg_hook "pre_unlink"; [ $? = 0 ] || return 1
  
  # remove link
  rm "$lib"/"$link_name"

  # remove old executables
  ls -A "$old_link"/bin 2> /dev/null | while read executable; do
    rm "$VPKG_HOME"/bin/"$executable"
  done
  
  # event
  _vpkg_hook "post_unlink"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg install [<options>] <package|url> [<build>] [<version>]
vpkg_install() {
  args=("$@")
  argue "-n, --name, +"\
        "-r, --rebuild" || return 1
  
  _vpkg_init_common || return 1
  
  # build
  vpkg build "$@"; [ $? = 0 ] || return 1
  
  # name may have changed
  _vpkg_import_name
  
  # link
  vpkg link "${args[@]}"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg uninstall [<options>] <package> [<build>]
vpkg_uninstall() {
  args=("$@")
  argue "-d, --destroy"\
        "-p, --purge" || return 1
  destroy="${opts[0]}"
  purge="${opts[1]}"
  
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # main
  vpkg unload "${args[@]}" &> /dev/null; [ $? = 0 ] || return 1
  vpkg unlink "${args[@]}" &> /dev/null; [ $? = 0 ] || return 1
  
  # --purge? --destroy?
  if [ -n "$purge" ]; then
    vpkg destroy "${args[@]}"; [ $? = 0 ] || return 1
    rm -rf "$VPKG_HOME"/etc/"$name"
    rm -rf "$VPKG_HOME"/src/"$name"
    rm -rf "$VPKG_HOME"/tmp/"$name"
    rm -rf "$etc"/.vpkg
  elif [ -n "$destroy" ]; then
    vpkg destroy "${args[@]}"; [ $? = 0 ] || return 1
  fi
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg load [options] <package|url> [<build>] [<version>]
vpkg_load() {
  args=("$@")
  argue "-n, --name, +" || return 1
  
  _vpkg_init_common || return 1
    
  # is anything suitable already loaded?
  [ -n "$build" ] && local search="$build" || local search="[^/]*"
  if echo "$PATH" | grep -q "$lib/$search/bin"; then
    build="$(echo "$PATH" | sed "s|.*$lib/\($search\)/bin.*|\1|")"
    echo "$name/$build: already loaded" >&2 && return 0
  fi
  
  # defaults
  _vpkg_init_defaults
  
  vpkg unload "$name" &> /dev/null; [ $? = 0 ] || return 1
  vpkg build "$@"; [ $? = 0 ] || return 1
  
  _vpkg_hook "pre_load"; [ $? = 0 ] || return 1
  
  # add package/version/bin to PATH
  [ -n "$PATH" ] && PATH=":$PATH"
  PATH="$lib"/"$build"/bin"$PATH"
  
  _vpkg_hook "post_load"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg unload <package> [<build>]
vpkg_unload() {
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1
  
  # don't unload unless loaded
  if ! echo "$PATH" | grep -q "$lib/[^/]*/bin"; then
    echo "$name: not loaded" >&2
    return 0
  elif [ -n "$build" ] && ! echo "$PATH" | grep -q "$lib/$build/bin"; then
    echo "$name/$build: not loaded" >&2
    return 1
  fi
  
  _vpkg_hook "pre_unload"; [ $? = 0 ] || return 1
  
  # edit PATH
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin:||g")"
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin||g")"
  
  _vpkg_hook "post_unload"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}
