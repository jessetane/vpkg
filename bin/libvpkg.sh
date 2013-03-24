#
# libvpkg.sh
#

vpkg_version() {
  echo "0.0.1"
}

vpkg_usage() {
  echo "usage: vpkg <command> [options] <package> [build] [version]"
}

vpkg_init_common() {
  
  # internal vars
  link_name="current"
  registry_cache="$VPKG_HOME"/etc/vpkg/registries
  recipe_cache="$VPKG_HOME"/etc/vpkg/recipes
}

vpkg_init_public() {
  
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

vpkg_init_defaults() {
  [ -z "$build" ] && export build="default"
  [ -z "$version" ] && export version="$build"
}

vpkg_update() {
  args=("$@")
  argue "-r, --registry-url, +" || return 1
  
  i=0
  registries="$VPKG_REGISTRIES"
  
  # respect --registry-url option
  [ -n "${opts[0]}" ] && registries="${opts[0]}"
  
  # sanity
  [ -z "$registries" ] && echo "specify a registry url with --registry-url or define VPKG_REGISTRIES" >&2 && return 1
  
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
  vpkg_init_public || return 1
  
  # update registries if the cache is empty
  if [ ! -e "$registry_cache" ] || [ -z "$(ls -A "$registry_cache")" ]
  then
    vpkg_update &> /dev/null || {
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
  
  done < <(ls "$registry_cache")
  
  # if we didn't get a url, that's an error
  [ -z "$recipe_url" ] && echo "$name: recipe not found" >&2 && return 1
  
  # print url to stdout
  echo "$recipe_url"
}

vpkg_get_recipe() {
  args=("$@")
  argue "-r, --recipe-url, +" || return 1
  vpkg_init_public || return 1
  
  recipe_url="${opts[0]}"
  recipe="$recipe_cache"/"$name"
  
  # ensure recipe cache exists
  mkdir -p "$recipe_cache"
  
  # are we missing a recipe url?
  if [ -z "$recipe_url" ]
  then
    
    # we only need to lookup a recipe url
    # if we don't already have a recipe
    if [ ! -e "$recipe" ]
    then
      recipe_url="$(vpkg_lookup "$name" 2> "$ipcfile")" || {
        
        # it's possible to build recipeless
        # packages if they have source files
        if [ -n "$(ls -A "$src")" ]
        then
          echo "warning: no recipe found, installing raw source files" >&2
        else
          cat "$ipcfile" >&2
          return 1
        fi
      }
    fi
  fi
  
  # if we get here and have a recipe_url we should try to download it
  if [ -n "$recipe_url" ]
  then
    echo "$name: downloading recipe from $recipe_url..."
    curl -fL# "$recipe_url" -o "$recipe" || return 1
  fi
}

vpkg_follow_recipe() {
  recipe="$recipe_cache"/"$name"
  
  if [ -e "$recipe" ]
  then
  
    # ensure our hookname is clean
    # XXX: i THINK eval is safe here...
    # XXX: export -f might be a bashism...
    eval "${cmd}() { return 127; }; export -f $cmd;"
    
    # if version = default, see if the recipe provides a default
    if [ "$version" = "default" ]
    then
      local temp="$(cmd="version" /bin/sh "$recipe")" && version="$temp"
    fi
    
    # follow the recipe
    /bin/sh "$recipe"
    recipe_status="$?"
    
    # check for errors
    if [ "$recipe_status" != 0 ]
    then
      
      # if the recipe returned 127 (command not found)
      # continue instead of just returning the error
      [ "$recipe_status" != 127 ] && return "$recipe_status"
    fi
  fi
  
  # if we get here, it worked
  return 0
}

vpkg_install() {
  args=("$@")
  argue "-r, --recipe-url, +"\
        "-l, --link"\
        "-f, --force" || return 1
  vpkg_init_public || return 1
  vpkg_init_defaults
  
  # uninstall first if --force
  if [ -n "${opts[2]}" ]
  then
    vpkg uninstall "$name" "$build"
  
  # if not forced, no build was spec'd, and a build is already linked, just return
  elif [ "$build" = "default" ] && [ -e "$lib"/"$link_name" ]
  then
    return 0
  fi
  
  # are we missing the build?
  if [ ! -e "$lib"/"$build" ]
  then
    
    # try to get a recipe
    vpkg get-recipe "$name" --recipe-url "${opts[0]}" || return 1
    
    # follow recipe
    vpkg_follow_recipe || return $?
    
    # install manually depending on what happened with the recipe
    if [ -z "$recipe_status" ] || [ "$recipe_status" = 127 ]
    then
      mkdir -p "$lib"
      cp -R "$src" "$lib"/"$build"
    fi
  fi
  
  # auto link if --link or no builds are already linked
  if [ -n "${opts[1]}" ] || [ ! -e "$lib"/"$link_name" ]
  then
    vpkg_link "$name" "$build"
  else
    return 0
  fi
}

vpkg_uninstall() {
  args=("$@")
  argue || return 1
  vpkg_init_public || return 1
  
  # sanity
  [ -z "$(ls -A "$lib" 2> /dev/null)" ] && echo "$name: no builds installed" >&2 && return 1
  
  # unlink
  vpkg unlink "$name" "$build" &> /dev/null
  
  # set defaults - be sure to do this after unlinking
  vpkg_init_defaults
  
  # hook
  vpkg_follow_recipe || return $?
  
  # uninstall manually depending on what happened with the recipe
  if [ -z "$recipe_status" ] || [ "$recipe_status" = 127 ]
  then
    [ -e "$lib"/"$build" ] && rm -rf "$lib"/"$build"
  fi
  
  # remove $name if no more builds
  [ -z "$(ls -A "$lib")" ] && rm -rf "$lib"
  
  # if we get here, it worked
  return 0
}

vpkg_link() {
  args=("$@")
  argue || return 1
  vpkg_init_public || return 1
  vpkg_init_defaults
  
  # sanity
  [ ! -e "$lib"/"$build" ] && echo "$name/$build: build is not installed" >&2 && return 1
  
  # unlink any builds already linked
  vpkg unlink "$name"
  
  # create link
  ln -s "$lib"/"$build" "$lib"/"$link_name"
  
  # create executables
  local executable
  ls "$lib"/"$version"/bin | while read executable
  do
    local dest="$VPKG_HOME"/bin/"$executable"
    
    # linking happens differently depending on whether the file is executable
    if [ -x "$lib"/"$build"/bin/"$executable" ]
    then
    
      # link via exec
      echo "exec ${lib}/${build}/bin/$executable "'$@' > "$dest"
      chmod +x "$dest"
    else
      
      # soft link
      ln -s "$lib"/"$build"/bin/"$executable" "$dest"
    fi
  done
  
  # PATH needs updating
  echo "$PATH" > "$ipcfile"
  return 78
}

vpkg_unlink() {
  args=("$@")
  argue || return 1
  vpkg_init_public || return 1
  
  old_link="$(readlink "$lib"/"$link_name")"
  
  # if a build was specified, check to ensure it's actually linked
  if [ -n "$build" ] && [ "$old_link" != "$lib"/"$build" ]
  then
    echo "$name/$build: build is not linked" >&2
    return 1
  fi
  
  # remove link
  rm -rf "$lib"/"$link_name"
  
  # remove old executables
  ls "$old_link"/bin | while read executable
  do
    rm -rf "$VPKG_HOME"/bin/"$executable"
  done
  
  # PATH needs updating
  echo "$PATH" > "$ipcfile"
  return 78
}

vpkg_load() {
  args=("$@")
  argue || return 1
  vpkg_init_public || return 1
  vpkg_init_defaults
  
  # prefer a linked build to a default build if there is one
  [ "$build" = "$default" ] && [ -e "$lib"/"$link_name" ] && build="$link_name"
  
  # sanity
  [ ! -e "$lib"/"$build" ] && echo "$name/$build: build is not installed" >&2 && return 1
  
  # unload any currently loaded versions first
  vpkg unload "$name"
  
  # don't place a ":" at the end of PATH
  [ -n "$PATH" ] && PATH=":$PATH"
  
  # add package/version/bin to PATH
  PATH="$lib"/"$build"/bin"$PATH"
  echo "$PATH" > "$ipcfile"
  
  # PATH needs updating
  return 78
}

vpkg_unload() {
  args=("$@")
  argue || return 1
  vpkg_init_public || return 1
  
  # remove package/build from PATH
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin:||g")"
  PATH="$(echo "$PATH" | sed "s|$lib/[^/]*/bin||g")"
  echo "$PATH" > "$ipcfile"
  
  # PATH needs updating
  return 78
}
