#!/usr/bin/env bash
#
# libvpkg.sh
#


# internal methods

_vpkg_init_private() {
  
  # internal vars
  link_name="current"
  registry_cache="$VPKG_HOME"/etc/vpkg/registries
  recipe_cache="$VPKG_HOME"/etc/vpkg/recipes
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
  local recipe="$recipe_cache"/"$name"
  local status=0
  
  # clear intercom
  echo "" > "$intercom"
  
  if [ -e "$recipe" ]; then
  
    # make sure $1 is safe for eval
    [ -z "$1" ] && echo "vpkg: hook not specified" >&2 && return 1
    
    # run in subshell for safety
    (
      # try to bail fast if things go south
      # be warned, set -e comes with caveats...
      set -e
      
      # make dir
      mkdir -p "$src"
      cd "$src"
      
      # ensure our hooks are clean
      eval "${1}() { :; }"
      version() { :; }
      
      # source recipe
      . "$recipe"
    
      # if version = default, see if the recipe provides a default
      if [ "$version" = "default" ]; then
        temp="$(version)" && version="$temp"
      fi
    
      # run hook
      "$1"
    )
    status="$?"
  fi
  
  # return status
  return "$status"
}


# public methods

vpkg_version() {
  echo "0.0.1"
}

vpkg_usage() {
  echo "usage: vpkg <command> [options] <package> [build] [version]"
}

# vpkg install [<options>] <package|url> [<build>] [<version>]
vpkg_install() {
  args=("$@")
  argue "-n, --name, +"\
        "-r, --rebuild" || return 1
  
  _vpkg_init_common || return 1
  
  # main
  vpkg build "$@"; [ $? = 0 ] || return 1
  vpkg link "${args[@]}"; [ $? = 0 ] || return 1
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
}

# vpkg uninstall [<options>] <package> [<build>]
vpkg_uninstall() {
  args=("$@")
  argue "-d, --destroy" || return 1
  destroy="${opts[0]}"
  
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # main
  vpkg unload "${args[@]}" &> /dev/null; [ $? = 0 ] || return 1
  vpkg unlink "${args[@]}" &> /dev/null; [ $? = 0 ] || return 1
  
  # --destroy?
  if [ -n "$destroy" ]; then
    vpkg destroy "${args[@]}"; [ $? = 0 ] || return 1
  fi
  
  # update PATH
  echo "$PATH" > "$intercom"
  return 78
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
        [ -e "$name" ] && echo "fetch: $name: source exists" >&2 && return 1
        cp -R "$VPKG_HOME"/src/"$url" "$VPKG_HOME"/src/"$name"
      fi
      return 0
    fi
  done < <(ls -A "$VPKG_HOME"/src)
  
  # we don't have source code yet so try to 
  # lookup the package from the registries
  lookup="$(vpkg lookup "$url")" && url="$lookup"
  
  # # is it git?
  # git ls-remote "$url" &> /dev/null && {
  #   git clone "$url" "$src"
  #   return 0
  # }
  
  # create a temp folder to download to
  tmp="$(mktemp -d "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" || {
    echo "fetch: could not create temporary directory" >&2 && return 1
  }
  cd "$tmp"
  
  # valid url?
  curl -I "$url" &> /dev/null || {
    echo "$url: package not registered and does not appear to be valid URL" >&2
    rm -rf "$tmp"
    return 1
  }
  
  # try to download file
  curl -fLO# "$url" || {
    rm -rf "$tmp" && return 1
  }
  
  # what'd we get?
  download="$(ls -A)"
  filetype="$(file "$download" | sed "s/.*: //")"

  # recipe (shell script)?
  if echo "$filetype" | grep -q "\(shell\|bash\|zsh\).*executable"; then
    mkdir -p "$recipe_cache"
    [ "$name" = "$url" ] && name="$(_vpkg_hook "name")"
    [ -z "$name" ] || {
      echo "$url: recipe did not provide a name, pass one manually with --name <package-name>" >&2
      rm -rf "$tmp" && return 1
    }
    cp "$download" "$recipe_cache"/"$name"
  
  # tarball?
  elif echo "$filetype" | grep -q "gzip compressed"; then
    tar -xvzf "$download" || {
      rm -rf "$tmp" && return 1
    }
    rm "$download"
    download="$(ls -A)"
    [ "$name" = "$url" ] && name="$download" && read -a name -p "$url: name this pacakge [$name]: "
    mv "$download" "$VPKG_HOME"/src/"$name"

  # zip archive?
  elif echo "$filetype" | grep -q "Zip archive"; then
    unzip "$download" || {
      rm -rf "$tmp" && return 1
    }
    rm "$download"
    download="$(ls -A)"
    [ "$name" = "$url" ] && name="$download" && read -a name -p "$url: name this pacakge [$name]: "
    mv "$download" "$VPKG_HOME"/src/"$name"
  
  # unknown
  else
    echo "fetch: unknown filetype: $filetype" >&2
    rm -rf "$tmp" && return 1
  fi

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
  
  # get source or recipe
  vpkg fetch "$name" --name "$rename"; [ $? = 0 ] || return 1
  [ -n "$rename" ] && name="$rename"
  
  # destroy if --rebuild
  if [ -n "$rebuild" ]; then
    vpkg destroy "$name" "$build"; [ $? = 0 ] || return 1
  fi
  
  # only build if we have to
  if [ ! -e "$lib"/"$build" ]; then
    mkdir -p "$lib"
    
    build_location="$(_vpkg_hook "pre_build")"; [ $? = 0 ] || return 1
    [ -z "$build_location" ] && build_location="$src"
    [ "$build_location" != "$lib"/"$build" ] && {
      cp -R "$build_location" "$lib"/"$build"
    }
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
  
  # def
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
  ls -A "$lib"/"$build"/bin | while read executable; do
    local dest="$VPKG_HOME"/bin/"$executable"
  
    # linking happens differently depending on whether the file is executable
    if [ -x "$lib"/"$build"/bin/"$executable" ]; then
    
      # link via exec
      echo "exec ${lib}/${build}/bin/$executable "'$@' > "$dest"
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
  ls -A "$old_link"/bin | while read executable; do
    rm "$VPKG_HOME"/bin/"$executable"
  done
  
  # event
  _vpkg_hook "post_unlink"; [ $? = 0 ] || return 1
  
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
  elif [ -n "$build" ] &&  ! echo "$PATH" | grep -q "$lib/$build/bin"; then
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
  return 1
  
  args=("$@")
  argue || return 1
  
  _vpkg_init_common || return 1
  
  # update registries if the cache is empty
  if [ ! -e "$registry_cache" ] || [ -z "$(ls -A "$registry_cache")" ]
  then
    vpkg update &> /dev/null || {
      echo 'warning: no registries found. try running `vpkg update`' >&2
      return 1
    }
  fi
  
  # attempt to lookup a url for $name from your registries
  while read registry
  do
  
    # in a subshell, source the registry and do a lookup
    recipe_url="$(
      unset "$name";
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
