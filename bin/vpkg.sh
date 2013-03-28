#
# vpkg.sh
#

vpkg() {
  
  # sanity
  [ -z "$VPKG_HOME" ] && echo "VPKG_HOME must be defined" >&2 && return 1
  
  # ensure tmp
  mkdir -p "$VPKG_HOME"/tmp
  
  # make a temporary file in case we need
  # to communicate with the subprocess
  local intercom="$(mktemp "$VPKG_HOME"/tmp/vpkg.XXXXXXXXX)" || {
    echo "could not create intercom" >&2 && return 1
  }
  
  # execute main in a subshell for environmental safety
  (
    # source deps
    . libargue.sh
    . libvpkg.sh
    
    # vars
    args=("$@")
    cmd="$1" && shift
    _vpkg_init_private
    
    case "$cmd" in
      
      # public sub commands
      "update") vpkg_update "$@";;
      "lookup") vpkg_lookup "$@";;
      "fetch") vpkg_fetch "$@";;
      "build") vpkg_build "$@";;
      "destroy") vpkg_destroy "$@";;
      "install") vpkg_install "$@";;
      "uninstall") vpkg_uninstall "$@";;
      "link") vpkg_link "$@";;
      "unlink") vpkg_unlink "$@";;
      "load") vpkg_load "$@";;
      "unload") vpkg_unload "$@";;

      # standalone mode
      *)

        # parse options
        argue "-v, --version"\
              "-h, --help" || return 1

        # if we have $cmd and no options
        if [ -n "$cmd" ] && [ "${#opts[@]}" = 0 ]
        then
          echo "$cmd: command not found" >&2 && return 1
        elif [ -n "${opts[0]}" ]
        then
          vpkg_version
        else
          vpkg_usage
        fi
    esac
  )
  
  # capture status
  local status="$?"
  
  # did the command want to update PATH?
  if [ "$status" = 78 ]
  then
    export PATH="$(cat "$intercom")"
    status=0
  fi

  # cleanup
  rm "$intercom"

  # report proper status
  return "$status"
}
