#!/bin/bash
# TEMPLATE_VERSION=2023-10-19

# Basic bash template for command/resource based CLI.
# Features:
# * Automatic command discovery and help generation
# * Logging and traces
# * Application dependency checker
# * Support for getopts
# * Return code support
# * Command executor with dry mode

set -eu

# App Global variable
# =================

APP_NAME="${0##*/}"
APP_AUTHOR="author"
APP_EMAIL="email@address.org"
APP_LICENSE="GPLv3"
APP_URL="https://github.com/$APP_AUTHOR/$APP_NAME"
APP_REPO="https://github.com/$APP_AUTHOR/$APP_NAME.git"
APP_GIT="git@github.com:$APP_AUTHOR/$APP_NAME.git"

APP_STATUS=alpha
APP_DATE="2023-01-01"
APP_VERSION=0.0.1

#APP_DEPENDENCIES="column tree htop"
APP_LOG_SCALE="TRACE:DEBUG:RUN:INFO:DRY:HINT:NOTICE:CMD:USER:WARN:ERR:ERROR:CRIT:TODO:DIE"

APP_DRY=${APP_DRY:-false}
APP_FORCE=${APP_FORCE:-false}
APP_LOG_LEVEL=${APP_LOG_LEVEL:-INFO}
#APP_LOG_LEVEL=DRY
#APP_LOG_LEVEL=DEBUG


# CLI libraries
# =================


_log ()
{
  local lvl="${1:-DEBUG}"
  shift 1 || true

  # Check log level filter
  if [[ ! ":${APP_LOG_SCALE#*$APP_LOG_LEVEL:}:$APP_LOG_LEVEL:" =~ :"$lvl": ]]; then
    if [[ ! ":${APP_LOG_SCALE}" =~ :"$lvl": ]]; then
      >&2 echo "  BUG: Unknown log level: $lvl"
    else
      return 0
    fi
  fi

  local msg=${*}
  if [[ "$msg" == '-' ]]; then
    msg="$(cat - )"
  fi
  while read -r -u 3 line ; do
    >&2 printf "%5s: %s\\n" "$lvl" "${line:- }"
  done 3<<<"$msg"
}

_die ()
{
    local rc=${1:-1}
    shift 1 || true
    local msg="${*:-}"
    if [[ -z "$msg" ]]; then
        _log DIE "Program terminated with error: $rc"
    else
        _log DIE "$msg"
    fi

    # Remove EXIT trap and exit nicely
    trap '' EXIT
    exit "$rc"
}

_exec ()
{
  local cmd=( "$@" )
  if ${APP_DRY:-false}; then
    _log DRY "  | ${cmd[@]}"
  else
    _log RUN "  | ${cmd[@]}"
    "${cmd[@]}"
  fi
}   


# shellcheck disable=SC2120 # Argument is optional by default
_dump_vars ()
{
  local prefix=${1:-APP_}
  declare -p | grep " .. $prefix" >&2 || {
      >&2 _log WARN "No var starting with: $prefix"
  }
}

_check_bin ()
{
  local cmd cmds="${*:-}"
  for cmd in $cmds; do
    command -v "$1" >&/dev/null || return 1
  done
}

# shellcheck disable=SC2120 # Argument is optional by default
_sh_trace ()
{
  local msg="${*}"

  (
    >&2 echo "TRACE: line, function, file"
    for i in {0..10}; do
      trace=$(caller "$i" 2>&1 || true )
      if [ -z "$trace" ] ; then
        continue
      else
        echo "$trace"
      fi
    done | tac | column -t
    [ -z "$msg" ] || >&2 echo "TRACE: Bash trace: $msg"
  )
}

# Usage: trap '_sh_trap_error $? ${LINENO} trap_exit 42' EXIT
_sh_trap_error () {
    local rc=$1
    [[ "$rc" -ne 0 ]] || return 0
    local line="$2"
    local msg="${3-}"
    local code="${4:-1}"
    set +x

    _log ERR "Uncatched bug:"
    _sh_trace # | _log TRACE -
    if [[ -n "$msg" ]] ; then
      _log ERR "Error on or near line ${line}: ${msg}; got status ${rc}"
    else
      _log ERR "Error on or near line ${line}; got status ${rc}"
    fi
    exit "${code}"
}

# Extra libs
# =================

# Ask the user to confirm
_confirm () {
  local msg="Do you want to continue?"
  >&2 printf "%s" "${1:-$msg}"
  >&2 printf "%s" "([y]es or [N]o): "
  >&2 read REPLY
  case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
    y|yes) echo "true" ;;
    *)     echo "false" ;;
  esac
}


# Ask the user to input string
_input () {
  local msg="Please enter input:"
  local default=${2-}
  >&2 printf "%s" "${1:-$msg}${default:+ ($default)}: "
  >&2 read REPLY
  [[ -n "$REPLY" ]] || REPLY=${default}
  echo "$REPLY"
}


_yaml2json ()
{
  python3 -c 'import json, sys, yaml ; y = yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))'
}

# CLI API
# =================

cli__help ()
{
  : ",Show this help"

  cat <<EOF
${APP_NAME:-${0##*/}} is command line tool

usage: ${0##*/} <COMMAND> <TARGET> [<ARGS>]
       ${0##*/} help

commands:
EOF

  declare -f | grep -E -A 2 '^cli__[a-z0-9_]* \(\)' \
    | sed '/{/d;/--/d;s/cli__/  /;s/ ()/,/;s/";$//;s/^  *: "//;' \
    | xargs -n2 -d'\n' | column -t -s ','

  cat <<EOF

info:
  author: $APP_AUTHOR ${APP_EMAIL:+<$APP_EMAIL>}
  version: ${APP_VERSION:-0.0.1}-${APP_STATUS:-beta}${APP_DATE:+ ($APP_DATE)}
  license: ${APP_LICENSE:-MIT}
EOF
}





# Return various system facts
_xsh_facts()
(

  FACT_PLATFORM=
  FACT_OS_NAME=
  FACT_OS_VERSION=
  FACT_ARCH=$(uname -m)


  FACT_SHELL=$(cut -d '' -f 1 /proc/$$/cmdline | sed 's@.*/@@')

    if [ "$(uname)" = "Darwin" ]; then
        FACT_PLATFORM=Darwin
        FACT_OS_NAME=macos
    elif [ "$(expr substr $(uname -s) 1 5)" = "Linux" ]; then
        FACT_PLATFORM=Linux

        if [ -e "/etc/os-release" ]; then
            source /etc/os-release
            if [ -n "$ID" ]; then
                FACT_OS_NAME=$ID
            fi
            if [ -n "$VERSION_ID" ]; then
                FACT_OS_VERSION=$VERSION_ID
            fi
        elif command -v lsb_release >/dev/null; then
            FACT_OS_NAME=$(lsb_release -si)
            FACT_OS_VERSION=$(lsb_release -sr)
        elif [ -e "/etc/lsb-release" ]; then
            source /etc/lsb-release
            FACT_OS_NAME=$DISTRIB_ID
            FACT_OS_VERSION=$DISTRIB_RELEASE
        else
            echo "Unable to determine OS and distribution."
            return 1
        fi
    elif [ "$(expr substr $(uname -s) 1 10)" = "MINGW32_NT" ] || [ "$(expr substr $(uname -s) 1 10)" = "MINGW64_NT" ]; then
        FACT_PLATFORM=Windows
        FACT_OS_NAME=windows
    else
        echo "Unable to determine OS and distribution."
        return 1
    fi
    # set -x
    # id -un 2>/dev/null

    local FACT_USERNAME=${USER:-$(id -un 2>/dev/null)} # || echo -n ${HOME##*/})}
    local FACT_USERID=$(id -u 2>/dev/null)
    local FACT_HOSTNAME=$(cat /proc/sys/kernel/hostname)
    local FACT_GROUPS=$(groups | tr ' ' ',')

    # set +x
    FACT_USER_ACCOUNT=unknown
    if [ "$FACT_USERID" -eq 0 ]; then
      FACT_USER_ACCOUNT=root
    elif [ "$FACT_USERID" -ge 1000 ]; then
        FACT_USER_ACCOUNT=user
    else
        FACT_USER_ACCOUNT=service
    fi

    local FACT_USER_SUDO=false
    if echo ",$FACT_GROUPS," | grep -Eq ",(wheel)|(sudo)|(admin),"; then
      FACT_USER_SUDO=true
    fi

    # Dump output
    declare | grep '^FACT_'
)




# Internal API
# =================

export XSHELL="${XSHELL:-${SHELL##*/}}"
export XSH_DIR="${XSH_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/xsh}"
export XSH_CONFIG_DIR="${XSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/shell}"
export XSH_RUNCOM_PREFIX="${XSH_RUNCOM_PREFIX:-@}"

export _XSH_LEVEL=${_XSH_LEVEL:-}



XSH2_MODULES='core,user-jez,user-root,ps1'
# Parse name order:
# - core
# - lib-*
# - shcfg-$SHELL
# - host-$NAME
# - user-$USER
# - conf-*
# - local-*
# - app-*
# Then scan priority for each mods:
#   mode_name/meta.env


# New FHS

# .shell/
#   $MODE_NAME:
#     $SHELL_$RUNCOM.$EXT

# SHELL can be one of:
# - sh
# - bash, fallback sh
# - zsh
# - fish
# - xonsh
# - elvish
# - OR - posix

_xsh_get_modules_conf ()
{
  local shell=$1
  # local mods=

  # echo "confs"
  # ls -ahl "$XSH_CONFIG_DIR/$shell"

  # echo "candidates"
  # local candidates=$(ls -1d "$XSH_CONFIG_DIR/$shell"/*/)
  # echo "$candidates"

  for mod in $(tr ',' ' ' <<< "$XSH2_MODULES"); do
    local mod_dir="$XSH_CONFIG_DIR/$shell/$mod/"
    [[ -d "$mod_dir" ]] || {
      _log WARN "Missing module '$mod' directory: $mod_dir"
      continue
    }
    # _log INFO "Load mod: $mod"
    # mods="${mods:+$mods,}$mod"

    local prio=50
    echo "$mod;$mod_dir;$prio"
  done

  # echo "mods=$mods"
}


# _xsh_get_modules_runcom_conf ()
# {
#   local shell=
# }

# _xsh_get_modules_runcoms_conf ()
# {
#   local shell=$1
#   local runcoms=$2

#   local mod_config=$(_xsh_get_modules_conf $shell)

#   for runcom in ${runcoms//,/ }; do
#     _log INFO "Load runcom $runcom"

#     while IFS=';' read -r mod_name mod_path mod_prio ; do
      
#       local target="${mod_path}${XSH_RUNCOM_PREFIX}${runcom}.bash"
#       # echo "YOOO: $target"

#       if [ -e "$target" ]; then
#         echo "# Load module: $target"
#         echo ". $target"
#       fi


#     done <<< "$mod_config"
  
#   done

# }



# # JEZ
# _xsh_shell_init_code() {
#   local shell=$1
#   local file=$2

#   echo "Show code to be sourced for shell: $shell-$file"

#   local xsh_loader="source '${XSH_DIR}/xsh.sh || return 1"

#   local out=
#   case "${shell}-${file}" in
#     bash-bashrc)
#       ;;
#     bash-bash_profile)


#       _xsh_init2

#       xsh runcom env
#       xsh runcom login
#       xsh runcom interactive

#       out="
# $xsh_loader

# ==========
# ${_XSH_LOAD_UNITS2[@]}
# ============

# xsh runcom env
# xsh runcom login

# # Bash does not read ~/.bashrc in a login shell even if it is interactive.
# [[ \$- == *i* ]] && xsh runcom interactive
# "
#       echo -e "$out"

#       ;;
#     bash-bashenv)
#       cat <<EOF
# $xsh_loader

# xsh runcom env
# EOF
#       ;;
#     bash-bash_logout)
#       cat <<EOF
# # It is assumed that $XSH_DIR/xsh.sh has been sourced.
# xsh runcom logout
# EOF
#       ;;
#     *)
#       _xsh_error "No such shell support: $shell-$file"
#       return 1
#     ;;
#   esac

#   # echo "MODULE;SHELLS;RUNCOMS ${_XSH_MODULES}" | tr ' ' '\n' | column -s ';' -t
# }


# CLI Commands
# =================

# cli__example ()
# {
#   : "[ARG],Example command"

#   local arg=${1}
#   echo "Called command: example $arg"
# }


# cli__init ()
# {
#   : "SHELL FILE,Show code to be sourced in shell"

#   _xsh_shell_init_code "$@"

# }


# cli__list_mods ()
# {
#   : "SHELL,Show code to be sourced in shell"

#   _xsh_get_modules_conf "$@"

# }







cli__gen ()
{
  : "lib:env:interactive:login:comp [SHELL],Show code to be sourced"


  local runcom=${1:-lib:env:interactive:login:comp}
  local shell=${2:-$FACT_SHELL}
  shift 2
  shell_dispatch $shell gen_code "$runcom" "$@"

}

cli__files ()
{
  : "lib:env:interactive:login:comp [SHELL],List files to be sourced"

  # _xsh_facts
  
  local runcom=${1:-lib:env:interactive:login:comp}
  local shell=${2:-$FACT_SHELL}
  shift 2
  shell_dispatch $shell lookup_files "$runcom" "$@"

}







##### Shell File lookup methods
#######################

MODULE_ORDER="xsh,shcfg-bash,user-jez,app-mise,app-direnv"

# Return the first file
first_found_file ()
{
  local files="$*"
  for file in "$@" ; do
    _log DEBUG "Looking for: $file"
    if [ -e "$file" ]; then
      echo "$file"
      return
    fi
  done
  echo "-"
}


# Show bash code to be sourced on shell init
shell__bash__gen_code ()
{

  local bin_dir='$HOME/.local/bin'
  local bin_dirs='$HOME/.local/scripts:'$bin_dir':$HOME/bin'
  cat <<EOF
# Update PATH
export PATH="$bin_dirs:\$PATH"

EOF


  echo '_OLD_PWD=$PWD'
  while IFS=';' read -r prj_dir file mod_name runcom mod_type; do
    echo "# Load: $mod_name/$runcom"
    echo "cd '$prj_dir' && . '$prj_dir/$file' || {"
    echo "  >&2 echo 'ERROR: While loading: $prj_dir/$file'"
    echo "}"
    # echo ". $prj_dir/$file"    
  done <<< "$(shell__bash__walk_files $1)"
  echo 'cd "$_OLD_PWD"; unset _OLD_PWD'
}


shell__bash__lookup_files ()
{
  # shell__bash__walk_files $1
  # return
  while IFS=';' read -r prj_dir file mod_name runcom mod_type; do
    # echo "# Load: $name/$runcom ($file)"
    echo -e "$prj_dir/$file\t\t\t$mod_name\t\t$runcom\t\t$mod_type"    
  done <<< "$(shell__bash__walk_files $1)"
}



## Engine tests
# ================

engine__ellipsis ()
{
  : "Support ellipsis.ch in: ~/.ellipsis/pkgs/*/ellipsis.sh"
}

engine__xsh ()
{
  : "Support xsh: ~/.local/xsh/SHELL/PKG/..."
}


engine__xdg ()
{
  : "Support .local/bashrc.d and ~/.bashrc.d/"
}


# MrJK Engine

engine__mrjk__enabled ()
{
  [ -d ".shell" ]
}


engine__mrjk__PATH ()
{
  : "Manage PATH dirs"
}

engine__mrjk__walk_files ()
{
  : "Support a mix between xsh and ellipsis"
  shell__bash__walk_files $1
}

engine__mrjk__gen_code ()
{
  echo 'Code to be sourced: WIP'
}


# Walk all potential files
shell__bash__walk_files ()
{
  # Show all targes
  
  local runcoms=$1
  local root_dir=$HOME/.shell
  local shell=bash

  local target=
  for runcom in ${runcoms//:/ }; do
    # echo "# Scan runcom: $runcom"

    
    # for mod_dir in $(ls -1d "$root_dir"/*/); do
    for mod_name in ${MODULE_ORDER//,/ }; do

      local prj_dir="$root_dir/$mod_name"
      local mod_dir="$prj_dir"
      local mod_type=simple
      if [ -d "$mod_dir/.shell" ]; then
        mod_dir="$mod_dir/.shell"
        mod_type=embedded
      fi
      local extra_files=()
      local base=(
            "${mod_dir}/bash_$runcom.bash" \
            "${mod_dir}/$runcom.bash" \
            "${mod_dir}/sh_$runcom.sh" \
            "${mod_dir}/posix_$runcom.sh" \
            "${mod_dir}/$runcom.sh" \
          )

      case "$runcom" in 
        comp)
          extra_files=(
            "${mod_dir}/bash_comp.sh.cache" \
            "${mod_dir}/comp.bash.cache" \
            "${mod_dir}/sh_comp.sh.cache" \
            "${mod_dir}/posix_comp.sh.cache" \
            )
          ;;
        lib)
          extra_files=(
            "${mod_dir}/${mod_name}.bash" \
            "${mod_dir}/${mod_name}.sh"
            )
          ;;
        *)
          ;;
      esac

      target=$(first_found_file "${extra_files[@]}" "${base[@]}")

      local subdir=${target#$prj_dir}
      local file=${subdir#/}
      subdir=${subdir%/$file}

      if [ "$target" != '-' ]; then
        # echo "$runcom;$mod_name;$target;$mod_type"
        echo "$prj_dir;$file;$mod_name;$runcom;$mod_type"
      fi

    done

  done


}

shell_dispatch ()
{
  local shell=$1
  local method=$2
  shift 2

  local cmd="shell__${shell}__${method}"

  if [ $(type -t "$cmd" || echo 'missing' ) = function ]; then
    _log INFO "Shell dispatch cmd: $cmd $@"
    $cmd "$@"
  else
    _die 3 "Unknown command: $cmd"
  fi

}


# Core App
# =================

app_init ()
{
  # Useful shortcuts
  export GIT_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
  export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  export WORK_DIR=${GIT_DIR:-${SCRIPT_DIR:-$PWD}}
  export PWD_DIR=${PWD}


  eval "$(_xsh_facts)"
}


app_main ()
{

  # Init
  trap '_sh_trap_error $? ${LINENO} trap_exit 42' EXIT
  
  # Read CLI options
  # Pleases check instead: https://github.com/TheLocehiliosan/yadm/blob/master/yadm#L769C1-L798C7
  local OPTIND opt
  while getopts "hnfv:" opt 2>/dev/null; do
    case "${opt}" in
        h)
          cli__help; _die 0 ;;
        n)
          _log INFO "Dry mode enabled"
          APP_DRY=true ;;
        f)
          _log INFO "Force mode enabled"
          APP_FORCE=true ;;
        v)
          _log INFO "Log level set to: $OPTARG"
          APP_LOG_LEVEL=$OPTARG ;;
        *)
          shift $((OPTIND-2))
          _die 1 "Unknown option: ${1}"
        ;;
    esac
  done
  shift $((OPTIND-1))

  # Route commands before requirements
  local cmd=${1:-help}
  shift 1 || true
  case "$cmd" in
    -h|--help|help) cli__help; return ;;
    # expl) cli__example "$@"; return ;;
  esac
  
  # Init app
  app_init
  
  # Define requirements
  local prog
  for prog in ${APP_DEPENDENCIES-} ; do
    _check_bin $prog || {
      _log ERROR "Command '$prog' must be installed first"
      return 2
    }
  done

  # Search and prepare command to run
  local args=${*:-}
  local commands=
  commands=$(declare -f | sed -E -n 's/cli__([a-z0-9_]*) *\(\).*/\1/p' | tr '\n' ':')
  if [[ ":$commands:" =~ .*":${cmd}:".* ]] ; then
    "cli__${cmd}" $args || {
      _die $? "Command returned error: $?"  
    }
  else
    _die 3 "Unknown command: $cmd"
  fi

}


app_main ${*:-}
