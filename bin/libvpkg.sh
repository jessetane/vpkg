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

_vpkg_run_hook() {
  local recipe="$recipe_cache"/"$name"
  local status=0
  
  if [ -e "$recipe" ]; then
  
    # run in subshell for safety
    (
      # make dir
      mkdir -p "$src"
      cd "$src"
      
      # ensure our hooks are clean - eval should be safe here
      eval "${1}() { return 127; }"
      version() { return 127; }
      
      # source recipe
      . "$recipe"
    
      # if version = default, see if the recipe provides a default
      if [ "$version" = "default" ]; then
        temp="$(version)" && version="$temp"
      fi
    
      # run hook
      "$1"
      status="$?"
      
      # command not found is OK
      [ "$status" = 127 ] && status=0
    )
  fi
  
  # return adjusted status
  return "$status"
}


# public methods 

vpkg_version() {
  echo "0.0.1"
}

vpkg_usage() {
  echo "usage: vpkg <command> [options] <package> [build] [version]"
}

vpkg_update() {
  echo "$cmd: not implemented"
}

vpkg_lookup() {
  echo "$cmd: not implemented"
}

vpkg_fetch() {
  
  # args/opts
  args=("$@")
  argue || return 1
  name="${args[0]}"
  source_name="${args[1]}"
  
  # 
}

# vpkg build [<options>] <package|url> [<build>] [<version>]
vpkg_build() {
  
  # args/opts
  args=("$@")
  argue "-n, --name, +"\
        "-r, --rebuild" || return 1
  source_name="${opts[0]}"
  rebuild="${opts[1]}"
  
  # init
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # main
  vpkg fetch "$name" "$source_name" || return 1
  [ -n "$rebuild" ] && vpkg destroy "$name" "$build"
  
  # only build if we have to
  if [ ! -e "$lib"/"$build" ]; then
    mkdir -p "$lib"
    build_location="$(_vpkg_run_hook "pre_build")" || return $?
    [ -z "$build_location" ] && build_location="$src"
    [ "$build_location" != "$lib"/"$build" ] && {
      cp -R "$build_location" "$lib"/"$build"
    }
    _vpkg_run_hook "post_build" || return $?
  fi
  
  # if we get here it worked
  return 0
}

# vpkg destroy <package> [<build>]
vpkg_destroy() {
  
  # args/opts
  args=("$@")
  argue || return 1
  
  # init
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # main
  vpkg unload "$@"
  vpkg unlink "$@"
  _vpkg_run_hook "pre_destroy" || return $?
  rm -rf "$lib"/"$build"
  _vpkg_run_hook "post_destroy" || return $?
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg link <package> [<build>]
vpkg_link() {
  
  # args/opts
  args=("$@")
  argue || return 1
  
  # init
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # error if build doesn't exist
  [ ! -e "$lib"/"$build" ] && echo "$name/$build: build is not installed" >&2 && return 1
  
  # nothing to do if already linked
  [ -e "$lib"/"$link_name" ] && [ "$(readlink "$lib"/"$link_name")" = "$build" ] && return 0
  
  # unlink any other linked builds for this package
  vpkg unlink "$name"
  
  # event
  _vpkg_run_hook "pre_link" || return $?
  
  # create link
  ln -sf "$lib"/"$build" "$lib"/"$link_name"
  
  # create executables
  local executable
  ls "$lib"/"$build"/bin | while read executable; do
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
  _vpkg_run_hook "post_link" || return $?
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg unlink <package> [<build>]
vpkg_unlink() {
  
  # args/opts
  args=("$@")
  argue || return 1
  
  # init
  vpkg_init_common || return 1
  old_link="$(readlink "$lib"/"$link_name")"
  
  # nothing to do if no builds are linked
  if [ "$?" != 0 ]; then
    return 0
    
  # if a build was specified, check to ensure it's actually linked
  elif [ -n "$build" ] && [ "$old_link" != "$lib"/"$build" ]; then
    echo "$name/$build: build is not linked" >&2
    return 1
  fi
  
  # event
  _vpkg_run_hook "pre_unlink" || return $?
  
  # remove link
  rm -rf "$lib"/"$link_name"

  # remove old executables
  ls "$old_link"/bin | while read executable; do
    rm -rf "$VPKG_HOME"/bin/"$executable"
  done
  
  # event
  _vpkg_run_hook "post_unlink" || return $?
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg install [<options>] <package|url> [<build>] [<version>]
vpkg_install() {
  
  # args/opts
  args=("$@")
  argue "-n, --name, +"\
        "-r, --rebuild" || return 1
  
  # init
  _vpkg_init_common || return 1
  
  # main
  vpkg build "$@" || return 1
  vpkg link "$@" || return 1
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg uninstall [<options>] <package> [<build>]
vpkg_uninstall() {
  
  # args/opts
  args=("$@")
  argue "-d, --destroy" || return 1
  destroy="${opts[0]}"
  
  # init
  _vpkg_init_common || return 1
  
  # main
  vpkg unload "${args[@]}"
  vpkg unlink "${args[@]}"
  [ -n "$destroy" ] && vpkg destroy "$@"
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg load [options] <package|url> [<build>] [<version>]
vpkg_load() {
  
  # args/opts
  args=("$@")
  argue "-n, --name, +" || return 1
  name="${opts[0]}"
  
  # init
  _vpkg_init_common || return 1
  _vpkg_init_defaults
  
  # don't load if already loaded
  echo "$PATH" | grep -q "$lib/$build/bin" && return 0
  
  vpkg unload "$name"
  vpkg build "$@"
  
  # main
  _vpkg_run_hook "pre_load" || return $?
  [ -n "$PATH" ] && PATH=":$PATH" # don't place a ":" at the end of PATH
  PATH="$lib"/"$build"/bin"$PATH" # add package/version/bin to PATH
  _vpkg_run_hook "post_load" || return $?
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}

# vpkg unload <package> [<build>]
vpkg_unload() {
  
  # args
  args=("$@")
  argue || return 1
  
  # init
  _vpkg_init_common || return 1
  
  # don't unload unless loaded
  if [ -n "$build" ]; then
    echo "$PATH" | grep -q "$lib/$build/bin" || return 0
  fi
  
  # main
  _vpkg_run_hook "pre_unload" || return $?
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin:||g")"
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin||g")"
  _vpkg_run_hook "post_unload" || return $?
  
  # update PATH
  echo "$PATH" > "$ipcfile"
  return 78
}
