#!/bin/sh

# If editing from Windows. Choose LF as line-ending

set -eu

# XDG Base Directory Specification
XDG_HOME=${XDG_HOME:-${HOME}};   # Not part of the specification, but useful
XDG_DATA_HOME=${XDG_DATA_HOME:-${XDG_HOME%%*/}/.local/share}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${XDG_HOME%%*/}/.config}
XDG_STATE_HOME=${XDG_STATE_HOME:-${XDG_HOME%%*/}/.local/state}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-${XDG_HOME%%*/}/.cache}

# Level of verbosity, the higher the more verbose. All messages are sent to the
# stderr.
UNGIT_VERBOSE=${UNGIT_VERBOSE:-0}

# UNGIT_TYPE can be set to either github or gitlab depending on the repository
# type. The default is to detect from the URL and when not possible, defaults to
# github.
UNGIT_TYPE=${UNGIT_TYPE:-}

# Default reference to use when none is specified.
UNGIT_DEFAULT_REF=${UNGIT_DEFAULT_REF:-main}

# When >=1 Force overwriting of existing files and directories, when >=2 force
# redownload of tarball even if in cache.
UNGIT_FORCE=${UNGIT_FORCE:-0}

# Keep the content of the target directory as is before extracting. Usually,
# this is just a bad idea. So it exists as a variable-driven option only.
UNGIT_KEEP=${UNGIT_KEEP:-0}

# Protect target directory and files from being changed by making them
# read-only. Boolean or auto (default) to turn on when index is used.
UNGIT_PROTECT=${UNGIT_PROTECT:-"auto"}

# Directory where to store the downloaded tarballs. Defaults to the directory
# called ungit in the XDG cache directory.
UNGIT_CACHE=${UNGIT_CACHE:-${XDG_CACHE_HOME}/ungit}

# Path to a file containing an index of all the snapshots created and from
# where. When empty, a file called .ungit will be created under the root of the
# git repository holding the destination directory, or none. When a dash, no
# index will be maintained, event in a git repository.
UNGIT_INDEX=${UNGIT_INDEX:-}

# Number of directories to look up for the .git directory. Set to -1 for no
# limit, and risk of infinite loop.
UNGIT_RFIND=${UNGIT_RFIND:-25}

# Token to use for authentication with the forge. When empty, no authentication
# will happen. When using tokens, the URL will be rewriten to the one of the API
# of each forge.
UNGIT_TOKEN=${UNGIT_TOKEN:-}

# Print usage out of content of main script and exit.
usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  if [ -z "${USAGE:-}" ]; then
    USAGE="Extract/maintain snapshots of git(hub/lab) repositories"
  fi
  printf "%s: %s\\n" "$(basename "$0")" "$USAGE" && \
    grep -E '^\s+[[:alnum:]])\s+#' "$0" |
    sed 's/#//' |
    sed -E 's/([[:alnum:]])\)/-\1\t/'
  cat <<EOF

Usage:
  $(basename "$0") [options] [command] [arguments]
  where [options] are as above, [command] is one of:
    install: Install all the snapshots listed in the index file
    add:     Add a snapshot of a repository to the index
    remove:  Remove a snapshot from the index (alias: delete, rm)
    help:    Print this help and exit

  When no known command is specified:
  + if no argument is specified, install is assumed.
  + if at least one argument is specified, add is assumed.
EOF
  printf \\nEnvironment:\\n
  set | grep '^UNGIT_' | sed 's/^UNGIT_/    UNGIT_/g'
  exit "${1:-0}"
}


while getopts "c:fi:p:r:t:T:vh-" opt; do
  case "$opt" in
    c) # Set the cache directory. Defaults to $XDG_CACHE_HOME/ungit. Empty to disable cache.
      UNGIT_CACHE=$OPTARG;;
    f) # Force overwriting of existing files and directories. Twice to force redownload of tarball even if in cache.
      UNGIT_FORCE=$((UNGIT_FORCE+1));;
    i) # Set the index file. Defaults to .ungit in the root of the git repository holding the destination directory. Use a dash to disable default.
      UNGIT_INDEX=$OPTARG;;
    p) # Protect target directory and files from being changed by making them read-only. Boolean or "auto" (default) to turn on when index is used.
      UNGIT_PROTECT=$OPTARG;;
    r) # Set the default reference, main by default
      UNGIT_DEFAULT_REF=$OPTARG;;
    t) # Force the repository type (github or gitlab), empty to autodetect from URL. Defaults to github
      UNGIT_TYPE=$OPTARG;;
    T) # Set the authentication token to use with the forge
      UNGIT_TOKEN=$OPTARG;;
    v) # Increase verbosity
      UNGIT_VERBOSE=$((UNGIT_VERBOSE+1));;
    h) # Print usage and exit
      usage;;
    -)
      break;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND-1))


# PML: Poor Man's Logging
_log() {
    printf '[%s] [%s] [%s] %s\n' \
      "$(basename "$0")" \
      "${2:-LOG}" \
      "$(date +'%Y%m%d-%H%M%S')" \
      "${1:-}" \
      >&2
}
trace() { if [ "${UNGIT_VERBOSE:-0}" -ge "3" ]; then _log "$1" TRC; fi; }
debug() { if [ "${UNGIT_VERBOSE:-0}" -ge "2" ]; then _log "$1" DBG; fi; }
verbose() { if [ "${UNGIT_VERBOSE:-0}" -ge "1" ]; then _log "$1" NFO; fi; }
warning() { _log "$1" WRN; }
error() { _log "$1" ERR && exit 1; }

# User-friendly boolean functions. True is not false,,,
is_false() { [ "$1" = "false" ] || { [ "$1" = "off" ] || [ "$1" = "0" ]; }; }
is_true() { ! is_false "$1"; }

# URL encode the string passed as a parameter
urlencode() {
  string=$1
  while [ -n "$string" ]; do
    tail=${string#?}
    head=${string%"$tail"}
    case $head in
      [-._~0-9A-Za-z]) printf %c "$head";;
      *) printf %%%02x "'$head"
    esac
    string=$tail
  done
  printf \\n
}

# Download the url passed as the first argument to the destination path passed
# as a second argument. The destination will be the same as the basename of the
# URL, in the current directory, if omitted.
download() {
  _URL=$1
  _TGT=${2:-$(basename "$1")}
  shift 2

  debug "Downloading $_URL to $_TGT"
  if command -v curl >/dev/null; then
    set -- -sSL -o "$_TGT" "$@" "$_URL"
    curl "$@"
  elif command -v wget >/dev/null; then
    set -- -q -O "$_TGT" "$@" "$_URL"
    wget "$@"
  else
    error "You need curl or wget installed to download files!"
  fi
}

# Call download as per the argument and verify that the downloaded file is a
# gzip file. If not, remove it. Return an error unless there is a (downloaded)
# gzip file.
download_gz() {
  download "$@"
  if [ -f "${2:-$(basename "$1")}" ]; then
    if ! gzip -t "${2:-$(basename "$1")}" 1>/dev/null 2>&1; then
      trace "Downloaded file ${2:-$(basename "$1")} is not a valid gzip file. Removing it!"
      rm -f "${2:-$(basename "$1")}"
      return 1
    fi
  else
    return 1
  fi
}

# Download the $REPO_URL at the $REPO_REF reference from GitHub. When a token is
# provided, rewrite the URL to point to the API URL and passed the token.
download_github_archive() {
  if [ -n "$UNGIT_TOKEN" ]; then
    # Add api. in front of the domain name and /repos/ in the path
    DW_ROOT=$(printf %s\\n "$REPO_URL" | sed -E 's~https://([[:alnum:].]+)/~https://api.\1/repos/~')
    download_gz "${DW_ROOT%/}/tarball/${REPO_REF}" "${1:-}" --header "Authorization: Bearer $UNGIT_TOKEN"
  else
    # Consider the reference to be a banch name first, then a tag name, then a
    # commit hash. Note: does not perform any check on the validity of the
    # reference. This could be done for commit references.
    download_gz "${REPO_URL%/}/archive/refs/heads/${REPO_REF}.tar.gz" "${1:-}" ||
      download_gz "${REPO_URL%/}/archive/refs/tags/${REPO_REF}.tar.gz" "${1:-}" ||
      download_gz "${REPO_URL%/}/archive/${REPO_REF}.tar.gz" "${1:-}"
  fi
}

# Download the $REPO_URL at the $REPO_REF reference from GitLab. Rely on
# GitLab's algorithm for resolving the reference to its real type: banch name,
# tag name, or commit hash.
download_gitlab_archive() {
  if [ -n "$UNGIT_TOKEN" ]; then
    # Extract the repository name from the URL and the root of the domain.
    _repo=$(printf %s\\n "$REPO_URL" | sed -E 's~https://([[:alnum:].:]+)/(.*)~\2~')
    DW_ROOT=$(printf %s\\n "$REPO_URL" | sed -E 's~https://([[:alnum:].:]+)/(.*)~https://\1/~')
    # Perform API call to get the archive URL and download it. For type to
    # .tar.gz, even though this is the default.
    download_gz "${DW_ROOT%/}/api/v4/projects/$(urlencode "$_repo")/repository/archive.tar.gz?sha=${REPO_REF}" "${1:-}" --header "PRIVATE-TOKEN: $UNGIT_TOKEN"
  else
    download_gz "${REPO_URL%/}/-/archive/${REPO_REF}/${REPO_NAME}-$(to_filename "${REPO_REF}").tar.gz" "${1:-}"
  fi
}

# If the repository reference at $REPO_REF from $REPO_URL is cached, copy it to
# the destination directory at $1, otherwise download.
cp_or_download() {
  if [ -n "${REPO_CACHE_PATH:-}" ] && [ -f "$REPO_CACHE_PATH" ]; then
    debug "Copying snapshot of $UNGIT_TYPE repository ${REPO_URL}@${REPO_REF} from $REPO_CACHE_PATH"
    cp "$REPO_CACHE_PATH" "$1"
  else
    debug "Downloading and extracting $UNGIT_TYPE repository at ${REPO_URL}@${REPO_REF}"
    "download_${UNGIT_TYPE}_archive" "$1"
  fi
}

# Convert a git reference to something that can be used as a filename. Replaces
# most non-alpha-numeric characters with a dash, as GitHub and GitLab do.
to_filename() {
  if [ $# -eq 0 ]; then
    tr -C '[:alnum:].:_' '-'
  else
    printf %s "$1" | to_filename
  fi
}

# Climb up the directory tree starting from $2 (or current dir), and look for
# the pattern at $1
climb_and_find() {
  if [ "$#" -gt 1 ]; then
    DIR=$2
  else
    DIR=$(pwd)
  fi
  RFIND_UP=$UNGIT_RFIND

  while [ "$DIR" != '/' ]; do
    find "$DIR" -maxdepth 1 -name "$1" -print 2>/dev/null
    DIR=$(dirname "$DIR")
    if [ "$RFIND_UP" -gt 0 ]; then
      RFIND_UP=$((RFIND_UP-1))
      if [ "$RFIND_UP" -eq 0 ]; then
        verbose "Reached max number of directories to look $1 in"
        break
      fi
    fi
  done
}

# Compute relative path from directory $1 to directory $2 (both directories need
# to exist).
relpath() {
  s=$(cd "${1%%/}" && pwd)
  d=$(cd "$2" && pwd)
  b=
  while [ "${d#"$s"/}" = "${d}" ]; do
    s=$(dirname "$s")
    b="../${b}"
  done
  printf %s\\n "${b}${d#"$s"/}"
}

# Look up the hierarchy of $1 for a .git directory to be able to turn on "git
# mode". Set the $GITROOT variable to the root location of the git repository
# this is called from and adapt the UNGIT_INDEX if none was specified.
# WARNING: This touches: GITROOT, UNGIT_INDEX, UNGIT_PROTECT->boolean
git_detect() {
  GITDIR=$(climb_and_find .git "$1" | head -n 1)
  if [ -z "$GITDIR" ]; then
    trace "Could not find a .git directory in $1"
    GITROOT=""
  else
    GITROOT=$(dirname "$GITDIR")
  fi

  # When none specified, set index as being a file called .ungit in the root of
  # the git repository.
  if [ "$UNGIT_INDEX" = "-" ]; then
    verbose "Indexing disabled"
    UNGIT_INDEX=""; # Switch off index completely.
  elif [ -z "$UNGIT_INDEX" ] && [ -n "$GITROOT" ]; then
    UNGIT_INDEX=${GITROOT}/.ungit
    verbose "Using $UNGIT_INDEX as index file"
  fi

  # Automatically turn target directory protection when applicable. Down from here
  # UNGIT_PROTECT can always be understood as a boolean.
  if [ "$UNGIT_PROTECT" = "auto" ]; then
    if [ -n "$UNGIT_INDEX" ]; then
      verbose "Turning on target directory protection"
      UNGIT_PROTECT=1
    else
      UNGIT_PROTECT=0
    fi
  fi
}


charcount() {
  printf %s\\n "$1" | grep -Fo "$2" | wc -l
}

protect() {
  if is_true "$UNGIT_PROTECT"; then
    chmod -R a-w "$1"
    debug "Hierarchically made $1 read-only"
  fi
}
unprotect() {
  if is_true "$UNGIT_PROTECT"; then
    chmod -R u+w "$1"
    debug "Hierarchically allowed user access to $1"
  fi
}

# Provided DESTDIR is a snapshot directory, update the index file to: add the
# repository it points to with $1, or remove it if no argument is provided
update_index() {
  if [ -n "$UNGIT_INDEX" ]; then
    INDEX_DIR=$(dirname "$UNGIT_INDEX")
    RELATIVE_DEST=$(relpath "$INDEX_DIR" "$DESTDIR")

    # Remove any reference to the target directory from the index
    idx=$(mktemp)
    if [ -f "$UNGIT_INDEX" ]; then
      grep -v "^$RELATIVE_DEST" "$UNGIT_INDEX" > "$idx" || true
    fi

    # Add the reference to the (new?) repository snapshot, if relevant
    if [ -n "${1:-}" ]; then
      printf '%s\t%s\n' "$RELATIVE_DEST" "$1" >> "$idx"
      verbose "Updated index ${UNGIT_INDEX}: $RELATIVE_DEST -> $1"
    else
      verbose "Removed index entry ${UNGIT_INDEX}: $RELATIVE_DEST"
    fi
    mv -f "$idx" "$UNGIT_INDEX"
  fi
}

cmd_install() {
  # Detect the git repository root and the index file
  git_detect "$(pwd)"
  if [ -n "$UNGIT_INDEX" ] && [ -f "$UNGIT_INDEX" ]; then
    # Copy the current index to a temporary file, as adding stuff might rewrite
    # to it otherwise.
    idx=$(mktemp)
    cp -f "$UNGIT_INDEX" "$idx"
    # Export all the UNGIT_ variables so as to make them available to the
    # subprocess. This is necessary since they carry the values of the
    # command-line options passed to this process.
    while IFS= read -r varname; do
      # shellcheck disable=SC2163 # We want to export the variable named in varname
      export "$varname"
    done <<EOF
$(set | grep -E '^UNGIT_[A-Z_]+=' | sed 's/=.*$//')
EOF
    # Read the index file and process each line
    INDEX_DIR=$(dirname "$UNGIT_INDEX")
    while IFS= read -r line || [ -n "${line:-}" ]; do
      # Skip leading comments and empty lines so the index can be hand-written
      # instead of just being generated.
      if [ "${line#\#}" != "$line" ]; then
        continue
      fi
      if [ -n "$line" ]; then
        # Read the destination directory and the repository URL from the index.
        DESTDIR=$(printf %s\\n "$line" | awk '{print $1}')
        REPO_URL=$(printf %s\\n "$line" | awk '{print $2}')
        if [ -n "$REPO_URL" ] && [ -n "$DESTDIR" ]; then
          # Compute the full path of the destination directory and call this
          # script again to add the snapshot. Do not replace existing
          # directories unless forced.
          DESTDIR=${INDEX_DIR}/${DESTDIR}
          if [ -d "$DESTDIR" ]; then
            if [ "$UNGIT_FORCE" -ge 1 ]; then
              "$0" add "$REPO_URL" "$DESTDIR"
            else
              verbose "Skipping $DESTDIR, already exists. Rerun with at least -f to force"
            fi
          else
            "$0" add "$REPO_URL" "$DESTDIR"
          fi
        fi
      fi
    done < "$idx"
    # Cleanup and exit, all work was done by the recursive calls.
    rm -f "$idx"
    exit
  else
    # No index file found, print usage and exit.
    usage 1>&2
  fi
}


cmd_add() {
  # If the first argument is a URL, use it as is, otherwise construct the full URL
  # using the UNGIT_TYPE variable, i.e. the type of the forge (github, gitlab,
  # etc.)
  if printf %s\\n "$1" | grep -qE '^https?://'; then
    REPO_URL=$1
  else
    if [ "$(charcount "$1" '/')" -ge 1 ]; then
      case "$UNGIT_TYPE" in
        gitlab)
          REPO_URL=https://gitlab.com/$1;;
        github)
          REPO_URL=https://github.com/$1
          ;;
        *)
          debug "Assuming github repository"
          UNGIT_TYPE=github
          REPO_URL=https://github.com/$1
          ;;
      esac
    else
      error "Invalid repository name: $1"
    fi
  fi
  shift

  # Extract the tag, branch or commit reference as being everything after the @
  REPO_REF=$(printf %s\\n "$REPO_URL" | grep -oE '@.*$' | cut -c 2-)
  if [ -z "$REPO_REF" ]; then
    REPO_REF=$UNGIT_DEFAULT_REF
  else
    REPO_URL=$(printf %s\\n "$REPO_URL" | sed 's/@.*$//')
  fi

  # Decide the destination directory. Construct a directory under the current
  # one using the base name of the repository if none is specified.
  REPO_NAME=${REPO_URL##*/}
  if [ $# -eq 0 ]; then
    DESTDIR=$(pwd)/$REPO_NAME
  else
    DESTDIR=$1
  fi

  # Lookup for a .git directory to be able to turn on "git mode"
  git_detect "$(dirname "$DESTDIR")"

  # Decide the repository type when none is specified, detect from the URL
  if [ -z "$UNGIT_TYPE" ]; then
    if printf %s\\n "$REPO_URL" | grep -q 'github\.com'; then
      UNGIT_TYPE=github
    elif printf %s\\n "$REPO_URL" | grep -q 'gitlab\.com'; then
      UNGIT_TYPE=gitlab
    else
      error "Unsupported repository type: $REPO_URL"
    fi
  fi

  # Decide upon the location of the tarball in the cache directory if one is
  # specified.
  if [ -n "$UNGIT_CACHE" ]; then
    mkdir -p "$UNGIT_CACHE"
    REPO_CACHE_PATH=${UNGIT_CACHE}/${UNGIT_TYPE}-$(to_filename "${REPO_NAME}")-$(to_filename "${REPO_REF}").tar.gz
    if [ -f "$REPO_CACHE_PATH" ] && [ "$UNGIT_FORCE" -ge 2 ]; then
      verbose "Removing cached snapshot $REPO_CACHE_PATH"
      rm -f "$REPO_CACHE_PATH"
    fi
  fi

  # Copy (from cache) or download the tarball to a temporary directory
  dwdir=$(mktemp -d)
  if cp_or_download "${dwdir}/${REPO_NAME}.tar.gz"; then
    debug "Written snapshot of ${REPO_URL}@${REPO_REF} to ${dwdir}/${REPO_NAME}.tar.gz"
  else
    rm -rf "$dwdir";  # Cleanup and exit
    error "Could not download ${REPO_URL}@${REPO_REF} to ${dwdir}/${REPO_NAME}.tar.gz"
  fi

  # Extract the tarball to a temporary directory
  tardir=$(mktemp -d)
  mkdir -p "$tardir"
  tar -xzf "${dwdir}/${REPO_NAME}.tar.gz" --strip-component 1 -C "$tardir"
  trace "Extracted ${dwdir}/${REPO_NAME}.tar.gz to $tardir"

  # Create the destination directory and copy the contents of the tarball to it.
  if [ -d "$DESTDIR" ]; then
    if [ "$UNGIT_FORCE" -ge 1 ]; then
      verbose "Removing all content from directory ${DESTDIR}"
      unprotect "$DESTDIR"
      rm -rf "$DESTDIR"
    elif is_true "$UNGIT_KEEP"; then
      verbose "Current directory content under ${DESTDIR} kept as-is"
      unprotect "$DESTDIR"
    else
      error "Destination directory ${DESTDIR} already exists. Use -f to overwrite"
    fi
  fi
  mkdir -p "${DESTDIR}"
  tar -C "${tardir}" -cf - . | tar -C "${DESTDIR}" -xf -
  verbose "Copied snapshot of ${REPO_URL}@${REPO_REF} to ${DESTDIR}"
  protect "$DESTDIR"

  # Keep a copy of the tarball in the cache directory if one is specified.
  if [ -n "$UNGIT_CACHE" ]; then
    verbose "Caching snapshot source as $REPO_CACHE_PATH"
    mv -f "${dwdir}/${REPO_NAME}.tar.gz" "$REPO_CACHE_PATH"
  fi

  # Maintain an index of all the snapshots created and from where.
  update_index "$REPO_URL"

  # Cleanup.
  rm -rf "$dwdir" "$tardir"
}


cmd_delete() {
  DESTDIR=$1;  # Make sure it is set
  if  [ -d "$DESTDIR" ]; then
    git_detect "$DESTDIR"
    update_index;  # Will remove the DESTDIR entry from the index
    verbose "Removing all content from directory ${DESTDIR}"
    unprotect "$DESTDIR"
    rm -rf "$DESTDIR"
  else
    error "Directory ${DESTDIR} does not exist"
  fi
}


# When arguments are given, look for an index file and process it, making sure
# the references that it contains are on disk.
if [ $# -eq 0 ]; then
  cmd_install
else
  # When arguments are given, look for a command and process it. When no command
  # is given, assume add.
  case "$1" in
    help)
      shift; usage;;
    install)
      shift; cmd_install;;
    add)
      shift; cmd_add "$@";;
    remove)
      shift; cmd_delete "$@";;
    delete)
      shift; cmd_delete "$@";;
    rm)
      shift; cmd_delete "$@";;
    *)
      # Default is to add a repository
      cmd_add "$@";;
  esac
fi
