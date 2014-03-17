#!/bin/dash

#################################################
#
# (c) 2014 Alexander E Genaud
#
# This work as-is I provide.
# No warranty express or implied.
# I've done my best,
# to debug and test.
# Liability for damages denied.
#
# Permission is granted hereby,
# to copy, share, and modify.
# Use as is fit,
# free or for profit.
# These rights, on this notice, rely.
#
###################################################
#
# rg - recursive git
#
# A backup, integrity, and overview tool based on
# git and a shell script.
#
#
# ======================
# Report and Synchronize
# ======================
#
# rg    [ TARGET ]   Check all drives and
#                      /home, synchronize and
#                      report comparison
#
# rg -d [ TARGET ]   Dry run. Report but
#                      do not synchronize
#
# rg -l [ TARGET ]   List. Report only
#
# rg -q [ TARGET ]   Quiet. Show only
#                      synchronizations
#
# rg -t [ TARGET ]   Test. No list, no synch,
#                      just perform unit tests
#
#
# ================
# Backup and clone
# ================
#
# rg -b TARGET  = bare, backup. Synchronize or
#              clone all to TARGET as bare repos
#
# rg -w TARGET  = work. Synchronize or clone all
#              to TARGET as working repos
#
# ================
# Catalogue
# ================
#
# rg -c TARGET  = catalogue each entire working tree
#
###################################################
#
# INSTALLATION
#
# On Windows/Cygwin, I recommend instead of adding
# the script to PATH, to create an alias of the
# form:
#
#   alias rg='export COLUMNS;dash $HOME/.rg/src/rg.sh'
#
###################################################

DEFAULT_REPO_WIDTH=65
DRYRUN=NO
QUIET=NO
LIST=NO
TEST=NO
TARGET=NO
BACKUP=NO
CATALOGUE=NO

############################################################
# get_arg
############################################################
get_arg() {
  if [ `echo "${1}_"|sed "s:^\(.\).*:\1:g"` = "-" ]; then
    if [ `echo "$1"|grep d|wc -l` = "1" ]; then DRYRUN=YES    ; fi
    if [ `echo "$1"|grep l|wc -l` = "1" ]; then LIST=YES      ; fi
    if [ `echo "$1"|grep q|wc -l` = "1" ]; then QUIET=YES     ; fi
    if [ `echo "$1"|grep t|wc -l` = "1" ]; then TEST=YES      ; fi
    if [ `echo "$1"|grep b|wc -l` = "1" ]; then _BACKBARE=YES ; fi
    if [ `echo "$1"|grep w|wc -l` = "1" ]; then _BACKWORK=YES ; fi
    if [ `echo "$1"|grep c|wc -l` = "1" ]; then CATALOGUE=YES ; fi
  elif [ "$TARGET" = "NO" ]; then
    TARGET="$1"
    return
  fi
  if   [ "_$_BACKBARE" = "_YES" ]; then BACKUP=BARE
  elif [ "_$_BACKWORK" = "_YES" ]; then BACKUP=WORK ; fi
}
if   [ $# -ge 1 ]; then get_arg "$1" ; fi
if [ $# -ge 2 -a "_$TARGET" = "_NO" ]; then TARGET="$2" ; fi

#
# Backup flag requires a unique TARGET
#
if [ "_$BACKUP" != "_NO" ]; then
  if [ "_$TARGET" = "_NO" ]; then
    echo rg: error: $BACKUP clone requires a target.
    echo "    Cloning all repositories into curent directory"
    echo "    requires an explicit dot ('.') such as:"
    echo
    if [ "_$BACKUP" = "_BARE" ]; then
         echo "     rg -b ."
    else echo "     rg -w ."   ; fi
    echo
    exit 1
  elif [ "_$TARGET" = "_/" ]; then
    echo rg: error: $BACKUP clone requires a unique target in
    echo "    which to clone all repositories into, such as:"
    echo
    if [ "_$BACKUP" = "_BARE" ]; then
         echo "     rg -b /home"
    else echo "     rg -w /home" ; fi
    echo
    exit 1
  fi
fi


############################################################
# initialize
############################################################
initialize() {
  #
  # on a windows machine, typically, WINROOT=c
  # on a Linux machine, we will set WINROOT=_
  #
  # calling 'resize' in Linux should export
  # the $COLUMNS env var. Does not work in Cygwin.
  # For pretty terminal width in Cygwin Suggestion:
  #
  #      alias rg='export COLUMNS;dash ~/.rg/src/rg.sh'
  #
  # In Windows, we need the HOME variable to henseforth
  # point to something like /cygdrive/c/Users/me
  #
  WINROOT='_'
  if [ "_${HOMEDRIVE}" != "_" ]; then # Windows
    WINROOT=`echo "${HOMEDRIVE}_"|cut -c 1|\
      tr '[:upper:]' '[:lower:]'`
    HOME=/cygdrive/${WINROOT}/Users/$USERNAME
    if [ "_$COLUMNS" = "_" ]; then
      #
      # reading COLUMNS from an interactive
      # shell is totally unreliable
      #
      #COLUMNS=$(bash -i ${HOME}/.rg/src/cygwin.columns.bash)
      echo rg: Terminal width unknown. Suggest export COLUMNS
      echo rg: alias rg='export COLUMNS;dash ~/.rg/src/rg.sh'
    fi
  elif [ "_$COLUMNS" = "_" ]; then # Linux
    eval $( resize )
  fi

  #
  # create some persistent and temp directories
  #
  # NB: HOME is the Linux/Cygwin HOME
  # further below we will normalize, for example
  # HOME=/home/u = /cygdrive/c/Users/u
  #
  DATADIR="${HOME}/.rg/data"
  CATADIR="${HOME}/.rg/catalogue"
  TEMPDIR="${HOME}/.rg/tmp/$$"
  TEMPDATA="${TEMPDIR}/data"
  mkdir -p "${DATADIR}"
  mkdir -p "${CATADIR}"
  mkdir -p "${TEMPDATA}"
  ORIGINAL_DIR=$PWD


  #
  # fit repo nicely in terminal window
  # Repo path shall be between 20 and 90 char wide
  #
  if [ "_$COLUMNS" =  "_" ]; then WIDTH_REPO=$DEFAULT_REPO_WIDTH
  elif [ $COLUMNS -le  60 ]; then WIDTH_REPO=20
  elif [ $COLUMNS -le 100 ]; then WIDTH_REPO=$(( $COLUMNS - 40 ))
  elif [ $COLUMNS -gt 100 ]; then WIDTH_REPO=75
  else WIDTH_REPO=$DEFAULT_REPO_WIDTH
  fi
}

############################################################
#
# parse_target
#
# ARGS
#     1. TARGET_ABSOLUTE          /some/path
#     2. WINROOT                  c|[a-z]|_
#
#     * on Windows WINROOT is typically 'c'
#       on Linux WINROOT='_'
#
# RETURN
#     TARGET_DEVICE
#     TARGET_REPO
#     RET=ERROR|OK
#
############################################################
parse_target() {
  if [ $# -ne 2 ]; then
    echo rg: Error in parse_target expects two arguments TARGET, OS
    exit 1
  fi
  PT_TARGET_ABSOLUTE=$1
  WINROOT=$2

  if [ "_$WINROOT" = "__" ]; then
    #
    # assume Linux machine
    #
    TARGET_DEVICE=`echo $PT_TARGET_ABSOLUTE |\
       grep    "^/\(home\|media/[^/]*\|mnt/[^/]*\)" |\
       grep -v "^/\(home\|m[a-t]*/[^/]*\)/\(Users\|home\)" |\
       sed   "s:^/\(home\|m[a-t]*/[^/]*\).*$:/\1:"`
    TARGET_REPO=`echo $PT_TARGET_ABSOLUTE |\
       grep    "^/\(home\|media/[^/]*\|mnt/[^/]*\)" |\
       grep -v "^/\(home\|m[a-t]*/[^/]*\)/\(Users\|home\)" |\
       sed -e "s:^/\(home\|m[a-t]*/[^/]*\)/*\(.*\)$:\2:"\
           -e "s:/*$::"`
  else
    #
    # assume Windows machine running cygwin
    #

    #
    # if Cygwin and /home/x then /cygdrive/y/Users/x
    #
    PT_TARGET_ABSOLUTE=`echo $PT_TARGET_ABSOLUTE |\
       sed "s:^/home:/cygdrive/${WINROOT}/Users:"`

    TARGET_DEVICE=`echo $PT_TARGET_ABSOLUTE |\
       grep    "^/cygdrive/[a-z]" |\
       grep    "^/cygdrive/\(${WINROOT}/Users\|[^${WINROOT}]\)" |\
       grep -v "^/cygdrive/[^${WINROOT}]/\(Users\|home\)" |\
       sed "s:^\(/cygdrive/\)\(${WINROOT}/Users\|[^${WINROOT}]\).*$:\1\2:"`
    TARGET_REPO=`echo $PT_TARGET_ABSOLUTE |\
       grep    "^/cygdrive/[a-z]" |\
       grep    "^/cygdrive/\(${WINROOT}/Users\|[^${WINROOT}]\)" |\
       grep -v "^/cygdrive/[^${WINROOT}]/\(Users\|home\)" |\
       sed -e "s:^\(/cygdrive/\)\(${WINROOT}/Users\|[^${WINROOT}]\)/*\(.*\)$:\3:"\
           -e "s:/*$::"`
  fi

  RET=ERROR
  if [ "_$PT_TARGET_ABSOLUTE" = "_/" -o "_$PT_TARGET_ABSOLUTE" = "_" ]; then
    RET=ERROR
  elif [ "_$TARGET_REPO" = "_" -a "_$PT_TARGET_ABSOLUTE" = "_$TARGET_DEVICE" ]; then
    RET=OK
  elif [ "_$PT_TARGET_ABSOLUTE" = "_${TARGET_DEVICE}/$TARGET_REPO" ]; then
    RET=OK
  else
    RET=ERROR
  fi
}

############################################################
# parse_target_assert
############################################################
parse_target_assert() {
  if [ $# -ne 5 ]; then
    echo rg: Error in parse_target_assert expects 5 arguments
    exit 1
  fi
  TARGET_ABSOLUTE=$1
  WINROOT=$2
  EXPECT_DEVICE=$3
  EXPECT_REPO=$4
  EXPECT_RET=$5
  parse_target "$TARGET_ABSOLUTE" "$WINROOT"
  if [ "_$EXPECT_DEVICE" = "_$TARGET_DEVICE" -a \
       "_$EXPECT_REPO"   = "_$TARGET_REPO" -a \
       "_$EXPECT_RET"    = "_$RET" ]; then
      printf 'OK   %-20s %-5s %-20s %-5s %-5s\n' \
        "\"${TARGET_ABSOLUTE}\"" "${WINROOT}" \
        "\"${TARGET_DEVICE}\"" "\"${TARGET_REPO}\"" "${RET}"
  else
      printf 'FAIL %-20s %-5s %-20s %-5s %-5s\n' \
        "\"${TARGET_ABSOLUTE}\"" "${WINROOT}" \
        "\"${TARGET_DEVICE}\"" "\"${TARGET_REPO}\"" "${RET}"
      printf '  Expected:%-20s %-20s %-5s %-5s\n' ' ' \
        "\"${EXPECT_DEVICE}\"" "\"${EXPECT_REPO}\"" "${EXPECT_RET}"
  fi
}


############################################################
# parse_target_test
############################################################
parse_target_test() {
  parse_target_assert \
    "/home"             "_" "/home"             ""      "OK"
  parse_target_assert \
    "/home/a"           "_" "/home"             "a"     "OK"
  parse_target_assert \
    "/media/a"          "_" "/media/a"          ""      "OK"
  parse_target_assert \
    "/media/a/b"        "_" "/media/a"          "b"     "OK"
  parse_target_assert \
    "/mnt/a"            "_" "/mnt/a"            ""      "OK"
  parse_target_assert \
    "/mnt/a/b"          "_" "/mnt/a"            "b"     "OK"
  parse_target_assert \
    "/media/home"       "_" "/media/home"       ""      "OK"
  parse_target_assert \
    "/media/Users"      "_" "/media/Users"      ""      "OK"
  parse_target_assert \
    "/mnt/home"         "_" "/mnt/home"         ""      "OK"
  parse_target_assert \
    "/mnt/Users"        "_" "/mnt/Users"        ""      "OK"
  parse_target_assert \
    "/mnt/hello world"  "_" "/mnt/hello world"  ""      "OK"

  parse_target_assert \
    ""                  "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/"                 "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/a"                "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/home/home"        "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/home/Users"       "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/media/a/home"    "_" ""                   ""      "ERROR"
  parse_target_assert \
    "/media/a/Users"   "_" ""                   ""      "ERROR"
  parse_target_assert \
    "/mnt/a/home"      "_" ""                   ""      "ERROR"
  parse_target_assert \
    "/mnt/a/Users"     "_" ""                   ""      "ERROR"
  parse_target_assert \
    "/cygdrive/c/Users" "_" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/x"       "_" ""                  ""      "ERROR"

  parse_target_assert \
    "/cygdrive/c/Users" "c" "/cygdrive/c/Users" ""      "OK"
  parse_target_assert \
    "/cygdrive/x"       "c" "/cygdrive/x"       ""      "OK"
  parse_target_assert \
    "/home"             "c" "/cygdrive/c/Users" ""      "OK"
  parse_target_assert \
    "/home/bob"         "c" "/cygdrive/c/Users" "bob"   "OK"

  parse_target_assert \
    ""                  "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/"                 "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/x"                "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive"         "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/c"       "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/c/x"     "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/x/Users" "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/x/home"  "c" ""                  ""      "ERROR"
  parse_target_assert \
    "/cygdrive/c/home"  "c" ""                  ""      "ERROR"
}

############################################################
#
# normalize_target
#
# RETURN
#     TARGET_DEVICE
#     TARGET_REPO
#
# or exits with a message
#
# TARGET_DEVICE is only important when cloning,
#   either as bulk bare (-b backup) or
#   bulk working directory (-w recover).
#   Example TARGET_DEVICE include: /home, /media/foo
#   /mnt/bar, /cygdrive/baz, or /cygdrive/c/Users
#
# TARGET_REPO is always significant. This is the
#   abstract repo such as alex/Music. In this case,
#   further processing would include alex/Music/Violin
#   but not alex/Photos/...
#
# Put together the TARGET resolves a TARGET_ABSOLUTE
# from which the TARGET_DEVICE and TARGET_REPO derive
#
# $ cd $HOME; rg Music
#
#    TARGET          = Music
#    TARGET_ABSOLUTE = /home/alex/Music
#    TARGET_DEVICE   = /home
#    TARGET_REPO     = alex/Music
#
#
# This function converts a relative TARGET to an
# absolute TARGET_ABSOLUTE and the subfunction
# 'parse_target' does all the heavy lifting.
#
############################################################
normalize_target() {
  #
  # if TARGET is not set, then assume the root directory
  # in other words, synchronize and list everything
  #
  if [ "_$TARGET" = "_"  -o "_$TARGET" = "_NO" -o \
       "_$TARGET" = "_/" -o "_$TARGET" = "_/." ]; then
    TARGET_DEVICE=$( echo $HOME|sed "s:/[^/]*$::" )
    TARGET_REPO=
    return
  fi

  if [ "_$TARGET" = "_." ]; then
    #
    # if the TARGET is a single dot, then it represents
    # the current working directory
    #
    TARGET_ABSOLUTE="$ORIGINAL_DIR"
  else
    #
    # otherwise, remove any trailing slashes or a single
    # trailing dot, but note that .. has special meaning
    #
    TARGET=`echo "$TARGET"|sed -e "s:\([^\.]\)\.$:\1:" -e "s:/*$::"`

    #
    # find absolute path from relative path, for example
    # relative path foo/bar might be absolute /home/foo/bar
    #
    if [ "0" = `echo $TARGET|grep "^/"|wc -l` ]; then
      # TARGET is relative
      TARGET_ABSOLUTE="${ORIGINAL_DIR}/$TARGET"
    else
      TARGET_ABSOLUTE="$TARGET"
    fi

    #
    # remove back paths (..), for example
    # convert /home/../var to absolute /var
    #
    _NUM_TRIES=20
    while [ `echo $TARGET_ABSOLUTE|grep "\.\."|wc -l` = "1" ]; do
      TARGET_ABSOLUTE=`echo $TARGET_ABSOLUTE|sed "s:/[^/]*/\.\.::"`
      _NUM_TRIES=$(( $_NUM_TRIES - 1 ))
      if [ "$_NUM_TRIES" = "0" ]; then break ; fi
    done
  fi

  #
  # remove trailing .git. Bare and working repositories
  # refer to the same abstract repo
  #
  TARGET_ABSOLUTE=`echo $TARGET_ABSOLUTE|sed "s:/*.git$::"`

  parse_target "$TARGET_ABSOLUTE" "$WINROOT"
  if [ "_$RET" = "_ERROR" ]; then
    echo rg: error parse_target bad target, should be at least
    echo "    /home, /media/x, /mnt/x, /cygdrive/x, or /cygdrive/c/Users/x"
    echo No data has been lost nor modified. Aborting
    exit 1
  fi
}

############################################################
# search_for_repos
############################################################
search_for_repos() {
  if [ "_$TARGET_REPO" = "_" ]; then
    TAIL=
    TAILGIT=
  else
    TAIL=/$TARGET_REPO
    TAILGIT=/${TARGET_REPO}.git
  fi

  #
  # The repo path might have spaces, so we
  # need to search each device individually
  #
  X=1
  if [ "_$WINROOT" != "__" ]; then
    # Windows, start with User home first
    find -P "/cygdrive/${WINROOT}/Users$TAIL" \
         "/cygdrive/${WINROOT}/Users$TAILGIT" \
          -type d -name "*.git" \
          2> /dev/null \
          | grep -v "^/cygdrive/./cyg[^/]*/home" \
          | sed "s:/*.git$::" \
          1> "${TEMPDIR}/"somerepos0 \
          2> /dev/null &
    # Windows, append all drives
    for d in `ls -d /cygdrive/*|grep -v /cygdrive/$WINROOT`; do
      find -P "${d}$TAIL" "${d}$TAILGIT" -type d -name "*.git" \
          2> /dev/null \
          | grep -v "^/cygdrive/./cyg[^/]*/home" \
          | sed "s:/*.git$::" \
          1>> "${TEMPDIR}/"somerepos$X \
          2> /dev/null &
      X=$(( $X + 1 ))
    done
  else # Linux
    find -P /home /media/* /mnt/* -maxdepth 0 -type d \
      2> /dev/null > "${TEMPDIR}/devicelist"
    while read d ; do
      find -P "${d}$TAIL" "${d}$TAILGIT" -type d -name "*.git" \
          2> /dev/null \
          | sed "s:/*.git$::" \
          1>> "${TEMPDIR}/"somerepos$X \
          2> /dev/null &
      X=$(( $X + 1 ))
    done < "${TEMPDIR}/devicelist"
  fi
  wait # each device search is in parallel
  cat "${TEMPDIR}/"somerepos* |\
    grep "^/\(home\|cygdrive/[a-z]\|media/[^/]*\|mnt/[^/]*\)/.*" >\
    "${TEMPDIR}/allrepos"
}

############################################################
# abstract_data
############################################################
abstract_data() {
  #
  # grab all unique devices which have git repositories
  #
  sed "s:^/\(home\|c[^/]*/./Users\|[cm][a-z]*/[^/]*\)/\(.*\)$:/\1:"\
      "${TEMPDIR}/allrepos" | sort | uniq 1> "${TEMPDIR}/devices"

  #
  # find the union of all abstract repositories
  # an abstract is just the path in common, for example
  #      /home/project
  #      /media/joker/project.git
  #      /cygdrive/c/Users/project
  #      /cygdrive/x/project
  # the abstract repo would be 'project'
  #
  sed "s:^/\(home\|c[^/]*/./Users\|[cm][a-z]*/[^/]*\)/\(.*\)$:\2:"\
      "${TEMPDIR}/allrepos" | sort | uniq 1> "${TEMPDIR}/abstractrepos"

  if [ "_$BACKUP" != "_NO" ]; then
    echo $TARGET_DEVICE >> "${TEMPDIR}/devices"
    sort "${TEMPDIR}/devices" | uniq 1> "${TEMPDIR}/tmp"
    mv "${TEMPDIR}/tmp" "${TEMPDIR}/devices"
  fi
}

############################################################
#
# label_devices
#
# each device may have a .label file at the root of its
# file tree. The first word of the first line is taken as
# the devices name. This function stores the devices and
# names in a file called temp/labels
#
############################################################
label_devices() {
  if [ "_${HOSTNAME}" = "_" ]; then HOSTNAME=$(hostname); fi
  while read device; do
    LABEL=
    if [ "_$device" = "_/home" ]; then
      #
      # On Linux, we name anything under /home
      # by the machine name (HOSTNAME)
      #
      echo "${HOSTNAME}:${device}" >> "${TEMPDIR}/labels"
    elif [ _`echo $device|grep "^/cygdrive/\([a-z]\|[a-z]/Users\)$"|wc -l` = "_1" ]; then
      if [ `echo $device|grep "^/cygdrive/$WINROOT"|wc -l` != "0" ]; then
        #
        # On Windows, we name anything under /cygdrive/c/Users
        # by the machine name (HOSTNAME). Note that 'c' is only
        # the typical case, WINROOT is based on the HOMEDRIVE
        # and HOMEPATH Windows environment variables
        #
        LABEL="${HOSTNAME}"
      elif [ -r "${device}/.label" ]; then
        #
        # On Windows, any other device, for example
        # /cygdrive/x will take the name from a .label
        # file at the device file system root, if it exists
        #
        LABEL=`head -1 "${device}/.label"|\
             sed "s:^\([a-zA-Z0-9][a-zA-Z0-9]*\).*$:\1:"|\
             grep "^[a-zA-Z0-9][a-zA-Z0-9]*$"`
      fi
      if [ "_$LABEL" = "_" ]; then
        #
        # On Windows, if we can't determine the label any
        # other way, then we'll accept the drive letter.
        # This sucks actually, because it's likely to change
        #
        LABEL=`echo $device|\
             sed "s:^/[^/]*/\([a-z]\)$:\1:"|\
             tr '[:lower:]' '[:upper:]'`
      fi
      echo "${LABEL}:${device}" >> "${TEMPDIR}/labels"
    elif [ "_`echo $device |\
           grep "^/\(media\|mnt\)/[^/][^/]*$"|\
           wc -l`" = "_1" ]; then
      #
      # On Linux, we name external devices found under
      # /media or /mnt by their .lable file
      #
      if [ -r "${device}/.label" ]; then
        LABEL=`head -1 "${device}/.label"|\
             sed "s:^\([a-zA-Z0-9][a-zA-Z0-9]*\).*$:\1:"|\
             grep "^[a-zA-Z0-9][a-zA-Z0-9]*$"`
      fi
      #
      # On Linux, if we cannot find the .label file,
      # we'll accept whatever name the OS (fstab) gave
      # it. This is not bad at all on most OS. However,
      # many bare bones OS (Debian) just assign /media/usb0
      # if it mounts the device at all.
      #
      if [ "_$LABEL" = "_" ]; then
        LABEL=`echo $device|sed "s:^/[^/]*/\([^/]*\)$:\1:"`
      fi
      echo "${LABEL}:${device}" >> "${TEMPDIR}/labels"
    fi
  done < "${TEMPDIR}/devices"
  sort "${TEMPDIR}/labels" | uniq > "${TEMPDIR}/tmp"
  mv "${TEMPDIR}/tmp" "${TEMPDIR}/labels"
}

############################################################
#
# _digits7
#
# _digit7( 5 ) ==> 0000005
#
############################################################
_digits7() {
  RET=`echo 0000000$1|sed "s:^.*\(.......\)$:\1:"`
}


############################################################
#
# summarize_one_repo
#
# RET example:
#
#     0000013:0000007
#
############################################################
summarize_one_repo() {
  FULLPATH=$1
  TYPE=$2

  if [ "_$TYPE" = "_BACKUP" ]; then
    RET="0000000:0000000"
    return
  fi

  cd "${FULLPATH}"

  # number of git log entries
  git log --oneline --graph  > "${TEMPDIR}/log"
  NUMLOG=`wc -l "${TEMPDIR}/log" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
  _digits7 $NUMLOG
  NUMLOG=$RET

  # number of unclean changes (modified, delete, untracked)
  NUMSTAT=0000000
  if [ "_$TYPE" = "_WORK" ]; then
    git status --short > "${TEMPDIR}/status"
    NUMSTAT=`wc -l "${TEMPDIR}/status" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
    _digits7 $NUMSTAT
    NUMSTAT=$RET
  fi

  # return to original directory
  cd "${ORIGINAL_DIR}"

  RET="${NUMLOG}:${NUMSTAT}"
}

############################################################
#
# catalogue_one_repo ( LOG_STATUS )
#
# input LOG_STATUS example:      0000013:0000007
#
# This method if called, writes a summary of all files
# in a repo to ~/.rg/catalogue
#
# Cataloging does nothing to each repo
# but it stores a SHA sum of every file
# based on each working directory.
# Very heavy operations. We check
# that both the user wants it (=YES)
# and a catalogue does not already exist
# for this repo version.
#
#
############################################################
catalogue_one_repo() {
  # catalogue_one_repo "$FULLPATH" "$repo" "$RET"
  CAT_FULLPATH=$1
  CAT_REPO=$2
  CAT_LOG_STATUS=$3

  CAT_PATH=${CATADIR}/${CAT_REPO}
  CAT_TARGET=${CAT_PATH}/${CAT_LOG_STATUS}

  # make the .rg/catalogue/path if it does not exist
  [ -d "$CAT_PATH" ] || mkdir -p "$CAT_PATH"

  # return if this exact repo has already been catalogued
  [ -r "$CAT_TARGET" ] && return

  #
  # traverse and digest the repo working tree
  #
  # TODO: must find a better way to filter out the .git directory
  #
  cd "${FULLPATH}"
  find * -type f -exec sha1sum {} \; | grep -v ".git" > "${CAT_TARGET}"
  cd "${ORIGINAL_DIR}"
}

############################################################
# summarize_similar_repos
############################################################
summarize_similar_repos() {
  repo="$1"
  SHOWSYNC="$2"

  ABBREV_LINE=""

  #
  # for each label:device
  #
  while read dev; do
    #
    # For each device, we see if the same repo exists and
    # if so, what type: bare, working, or future backup
    #
    LABEL=`echo $dev|cut -d: -f1`
    DEVICE=`echo $dev|cut -d: -f2`
    ABBREV=`echo $LABEL|sed "s:^\(.\).*:\1:"`
    FULLPATH=
    TYPE=
    if [ -d "${DEVICE}/${repo}.git" ]; then
      FULLPATH="${DEVICE}/${repo}.git"
      TYPE=BARE
      ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
    elif [ -d "${DEVICE}/${repo}/.git" ]; then
      FULLPATH="${DEVICE}/${repo}"
      TYPE=WORK
      ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
    elif [ "_$BACKUP" != "_NO" -a "_$DEVICE" = "_${TARGET_DEVICE}" -a \
      `echo ${repo}|grep "^$TARGET_REPO"|wc -l` = "1" ]; then
        # this device does not have this repository
        # add a blank space to the abbreviation line
      FULLPATH="${DEVICE}/${repo}"
      TYPE=BACKUP
      ABBREV_LINE="${ABBREV_LINE} "
    else
      ABBREV_LINE="${ABBREV_LINE} "
      continue
    fi

    #
    # get the number of log line and status of particular repo
    # such as   0000013:0000007
    #
    summarize_one_repo "$FULLPATH" "$TYPE"

    #
    # Cataloging does nothing to the repos
    # but it stores a SHA sum of every file
    # based on each working directory.
    # Very heavy operations. We check
    # that both the user wants it (=YES)
    # and the repo is a working copy and,
    # in the method, check that a
    # catalogue does not already exist
    # for this repo version.
    #
    if [ "_$CATALOGUE" = "_YES" -a "_$TYPE" = "_WORK" ]; then
      catalogue_one_repo "$FULLPATH" "$repo" "$RET"
    fi

    #
    # add the label and abstract repo to its own file in
    # storage, like so:
    #    0000013:0000007:alice:foo/bar
    # after synch (if we do so), these files will be copied
    # and stored permanently.
    #
    echo "${RET}:${LABEL}:${repo}" > "${TEMPLINEDATA}/${LABEL}"

    #
    # also store this repo in a single file (ranksync)
    # that we will later sort from newest to oldest.
    # We store the type and full path so that we can later
    # synch the oldest toward the newest.
    # Push or pull depending on type: bare or working
    #
    NUMLOG=`echo $RET|cut -d: -f1`
    NUMSTAT=`echo $RET|cut -d: -f2`
    echo "${RET}:${TYPE}:${FULLPATH}" >> "${TEMPLINE}/ranksync"

    #
    # Here we group lines with the same log status
    # such that 12:0:a and 12:0:b becomes 12:0:a,b
    #
    RANKFILE="${TEMPLINE}/rankabbrev${NUMLOG}_${NUMSTAT}"
    if [ -r "$RANKFILE" ]; then
      #Example:      9:13!a,b
      echo `head -1 "$RANKFILE"`,$ABBREV > "$RANKFILE"
    else
      # CAT_DIVIDER   9:0:a   or   9:0!a
      #
      # ":" indicates that the catalogue does exist for
      # this repo version. Example   9:0:a
      #
      # "!" indicates that the catalogue does not exist for
      # this repo version (which could easily be the case if
      # this method was never called). Example  9:0!a
      if [ -r "${CATADIR}/${repo}/${NUMLOG}:${NUMSTAT}" ]; then
        CAT_DIVIDER=":"
      else CAT_DIVIDER="!" ;  fi

      # reduce NUMLOG and NUMSTAT from for example
      # 0000009:0000013 to 9:13
      NUMLOG=`echo $NUMLOG|sed "s:^0*::"`
      if [ "_$NUMLOG" = "_" ]; then NUMLOG=0; fi
      NUMSTAT=`echo $NUMSTAT|sed "s:^0*::"`
      if [ "_$NUMSTAT" = "_" ]; then NUMSTAT=0; fi

      #Example:      9:13!a
      echo "${NUMLOG}:${NUMSTAT}${CAT_DIVIDER}${ABBREV}" > "$RANKFILE"
    fi

  done < "${TEMPDIR}/labels"

  FIRST=YES
  RET="${ABBREV_LINE}"

  # Show the device abbreviations such as (abc)
  # unless synchronizing (===) or failure (!!!)
  if   [ "_$SHOWSYNC" = "_SYNC" ]; then
    RET=`echo "$RET"|sed "s:.:=:g"`
  elif [ "_$SHOWSYNC" = "_FAIL" ]; then
    RET=`echo "$RET"|sed "s:.:!:g"`
  fi

  # Add the rest of the line. If the first rank, then
  #
  # RET=ABBREV REPO/PATH 9:0:a,b
  #
  # Subsequent ranks are tacked on such as
  # "> 9:0:c" giving us something like
  #
  # RET=ABBREV REPO/PATH 9:0:a,b > 8:3:d > 7:5:c
  #
  for file in `ls "${TEMPLINE}"/rankabbrev*|sort -r`; do
    FILE=`cat "$file"`
    if [ "$FIRST" = "YES" ]; then
      # Example:     ABBREV REPO/PATH 9:0:a,b
      RET=$(printf "${RET} %-${WIDTH_REPO}s $FILE" "$repo")
      FIRST=NO
    else
      # Example:     ABBREV REPO/PATH 9:0:a,b > 8:3:d
      # Example:     ABBREV REPO/PATH 9:0:a,b > 8:3:d > 7:5:c
      RET="${RET} > ${FILE}"
    fi
  done
}

############################################################
# summarize_precomputed_repos
############################################################
summarize_precomputed_repos() {
  repo="$1"

  ABBREV_LINE=""

  #
  # for each label
  #
  while read dev; do
    LABEL=`echo $dev|cut -d: -f1`
    ABBREV=`echo $LABEL|sed "s:^\(.\).*:\1:"`

    #0000004:0000000:ARCH_201311:foobar
    LINE=`grep ":${repo}$" "${DATADIR}/$LABEL"`

    if [ "_`echo $LINE|wc -c`" != "_1" ]; then
      ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
    else
      # add a blank space to the abbreviation line
      ABBREV_LINE="${ABBREV_LINE} "
      continue
    fi

    NUMLOG=`echo $LINE|cut -d: -f1`
    NUMSTAT=`echo $LINE|cut -d: -f2`

    #
    # Here we group lines with the same log status
    # such that 12:0:a and 12:0:b becomes 12:0:a,b
    #
    RANKFILE="${TEMPLINE}/rankabbrev${NUMLOG}_${NUMSTAT}"
    if [ -r "$RANKFILE" ]; then
      #Example:      9:13!a,b
      echo `head -1 "$RANKFILE"`,$ABBREV > "$RANKFILE"
    else
      # CAT_DIVIDER   9:0:a   or   9:0!a
      #
      # ":" indicates that the catalogue does exist for
      # this repo version. Example   9:0:a
      #
      # "!" indicates that the catalogue does not exist for
      # this repo version (which could easily be the case if
      # this method was never called). Example  9:0!a
      if [ -r "${CATADIR}/${repo}/${NUMLOG}:${NUMSTAT}" ]; then
        CAT_DIVIDER=":"
      else CAT_DIVIDER="!" ;  fi

      # reduce NUMLOG and NUMSTAT from for example
      # 0000009:0000013 to 9:13
      NUMLOG=`echo $NUMLOG|sed "s:^0*::"`
      if [ "_$NUMLOG" = "_" ]; then NUMLOG=0; fi
      NUMSTAT=`echo $NUMSTAT|sed "s:^0*::"`
      if [ "_$NUMSTAT" = "_" ]; then NUMSTAT=0; fi

      #Example:      9:13!a
      echo "${NUMLOG}:${NUMSTAT}${CAT_DIVIDER}${ABBREV}" > "$RANKFILE"
    fi

  done < "${TEMPDIR}/labels"

  FIRST=YES
  RET="${ABBREV_LINE}"

  # Add the rest of the line. If the first rank, then
  #
  # RET=ABBREV REPO/PATH 9:0:a,b
  #
  # Subsequent ranks are tacked on such as
  # "> 9:0:c" giving us something like
  #
  # RET=ABBREV REPO/PATH 9:0:a,b > 8:3:d > 7:5:c
  #
  for file in `ls "${TEMPLINE}"/rankabbrev*|sort -r`; do
    FILE=`cat "$file"`
    if [ "$FIRST" = "YES" ]; then
      # Example:     ABBREV REPO/PATH 9:0:a,b
      RET=$(printf "${RET} %-${WIDTH_REPO}s $FILE" "$repo")
      FIRST=NO
    else
      # Example:     ABBREV REPO/PATH 9:0:a,b > 8:3:d
      # Example:     ABBREV REPO/PATH 9:0:a,b > 8:3:d > 7:5:c
      RET="${RET} > ${FILE}"
    fi
  done
}

##################################################
#
# synchronize_similar_repos
#
# returns RET [ NONE | SYNC ]
#    NONE means no change, no synchronization
#    SYNC means at least one repo was updated
#
##################################################
synchronize_similar_repos() {
  SYNC_ORIGDIR="${PWD}"
  LATEST=YES

  # 0000004:0000001:WORK:/home/alex/.rg/bin
  sort -r "${TEMPLINE}/ranksync" > "${TEMPLINE}/sort"

  while read RANK; do
    #
    # read the log, status numbers, type (bare,
    # working, future backup) from latest (top)
    # to oldest, sorted from ranksync file (from
    # earlier compare function)
    #
    LOGNUM=`echo $RANK|cut -d: -f1|sed "s:^0*::"`
    if [ "_$LOGNUM" = "_" ]; then LOGNUM=0; fi

    STATNUM=`echo $RANK|cut -d: -f2|sed "s:^0*::"`
    if [ "_$STATNUM" = "_" ]; then STATNUM=0; fi

    TYPE=`echo $RANK|cut -d: -f3`
    FULLPATH=`echo $RANK|cut -d: -f4`

    if [ "$LATEST" = "YES" ]; then
      #
      # the top line is the (or one of the) latest
      # clone of the otherwise similar repos. We'll
      # synchronize all others with this top repo.
      #
      LATEST_LOGNUM=$LOGNUM
      LATEST_TYPE=$TYPE
      LATEST_FULLPATH=$FULLPATH
      LATEST=NO
      continue
    elif [ "_$STATNUM" != "_0" \
      -o "_$LOGNUM" = "_$LATEST_LOGNUM" ]; then
      #
      # can only fast forward a clean repo
      # and dont bother synching already synched
      #
      continue
    elif [ "_$TYPE" = "_BACKUP" ]; then
      #
      # This repo does not yet exist. The user
      # has requested a backup in on this device
      # in this target sub-path. Bare flag and tail
      # are trick values. For a working repo, these
      # values are blank and will have no effect. For
      # a bare repo, they'll add a "clone --bare" and
      # a ".git" suffix to the repo directory name.
      #
      BAREFLAG=
      BARETAIL=
      if [ "_$BACKUP" = "_BARE" ]; then
        BAREFLAG=" --bare "
        BARETAIL=".git"
      fi
      #
      # Parent path is one above the target repo.
      # If we want to create foo/bar/baz.git,
      # then we must first ensure that foo/bar
      # exists. Then we can clone baz into bar.
      #
      PARENTPATH=`echo $FULLPATH|sed "s:/[^/]*$::"`
      echo ${FULLPATH}${BARETAIL} clone of $LATEST_FULLPATH >> "${TEMPDIR}/gitstdout"
      if [ "_$DRYRUN" = "_YES" ]; then
        echo "    ${FULLPATH}${BARETAIL} clone of $LATEST_FULLPATH"
      elif [ -d "${FULLPATH}" -o -d "${FULLPATH}${BARETAIL}" ]; then
        #
        # Check that we can actually clone here. Git will refuse
        # to clone into an existing directory (god bless).
        #
        RET="FAIL"
      else
        mkdir -p "$PARENTPATH"
        git clone $BAREFLAG "$LATEST_FULLPATH" "${FULLPATH}${BARETAIL}" \
          1>> "${TEMPDIR}/gitstdout" 2> "${TEMPDIR}/gitstderr"
        # git clone can fail if not enough memory or extant directory
        if [ `grep fatal "${TEMPDIR}/gitstderr"|wc -l` -gt 0 ]; then
          RET="FAIL"; else RET="SYNC"; fi
      fi
    elif [ "_$TYPE" = "_WORK" ]; then
      #
      # This repo already exists, but it is old
      # out-of-date. It is a working directory,
      # so we have to __pull__ from the latest
      #
      cd "$FULLPATH"
      echo $FULLPATH pull from $LATEST_FULLPATH >> "${TEMPDIR}/gitstdout"
      if [ "_$DRYRUN" = "_YES" ]; then
        echo "    $FULLPATH" pull from "$LATEST_FULLPATH"
      else
        git pull --ff-only "$LATEST_FULLPATH" master \
          1>> "${TEMPDIR}/gitstdout" 2> "${TEMPDIR}/gitstderr"
      fi
      # git pull will fail if not fast-forward
      if [ `grep "\(fatal\|rejected\).*fast-forward" "${TEMPDIR}/gitstderr"|wc -l` -gt 0 ]; then
        RET="FAIL"; else RET="SYNC"; fi
    elif [ "_$TYPE" = "_BARE" ]; then
      #
      # This repo already exists, but it is old
      # out-of-date. It is a bare directory,
      # so we have to __push__ from the latest
      #
      cd "$LATEST_FULLPATH"
      echo $LATEST_FULLPATH push to $FULLPATH >> "${TEMPDIR}/gitstdout"
      if [ "_$DRYRUN" = "_YES" ]; then
        echo "    $LATEST_FULLPATH" push to "$FULLPATH"
      else
        git push "$FULLPATH" master \
          1>> "${TEMPDIR}/gitstdout" 2> "${TEMPDIR}/gitstderr"
      fi
      # git pull will fail if not fast-forward
      if [ `grep "\(fatal\|rejected\).*fast-forward" "${TEMPDIR}/gitstderr"|wc -l` -gt 0 ]; then
        RET="FAIL"; else RET="SYNC"; fi
    fi
  done < "${TEMPLINE}/sort"
  cd "${SYNC_ORIGDIR}"
}

############################################################
# compare_repos
############################################################
compare_repos() {
  TEMPLINE=${TEMPDIR}/line
  TEMPLINEDATA=${TEMPDIR}/linedata
  while read repo; do
    #
    # cleanup the TEMPLINE and TEMPLINEDATA directories
    # This is necessary, because we will enter the
    # compare_repos function many times: Perhaps twice,
    # before and after synchronization, and for each
    # abstract (common) repo.
    #
    if [ -d "${TEMPLINE}" ]; then
         rm -rf "${TEMPLINE}"/*
    else mkdir -p "${TEMPLINE}"
    fi

    if [ -d "${TEMPLINEDATA}" ]; then
         rm -rf "${TEMPLINEDATA}"/*
    else mkdir -p "${TEMPLINEDATA}"
    fi

    #
    # report a single log status line for all similar repos
    #
    #  ryu  foo/bar 5:8:u > 3:0:r,y
    # cry z my/repo 12:0:y > 10:3:c > 9:0:r,z
    #
    summarize_similar_repos "$repo" "NoSync"
    if [ "_$QUIET" = "_NO" ]; then echo "$RET"
    else PREVLINE=$RET
    fi

    #
    # synchronize any clean (not status lines:
    #    modified, removed, added, untracked)
    # up to the latest similar repository. Example:
    #
    #  ryu  foo/bar 5:8:u > 5:0:r,y
    # cry z my/repo 12:0:r,y,z > 10:3:c
    #
    synchronize_similar_repos "$repo"
    if [ "_$RET" = "_SYNC" -o "_$RET" = "_FAIL" ]; then
      if [ "_$QUIET" = "_YES" ]; then echo $PREVLINE ; fi
      rm -rf "${TEMPLINE}"/* "${TEMPLINEDATA}"/*
      #
      # if there was any synchronization,
      # then compare and display again
      #
      #  ryu  foo/bar 5:8:u > 3:0:r,y
      # ===== foo/bar 5:8:u > 5:0:r,y
      # cry z my/repo 12:0:y > 10:3:c > 9:0:r,z
      # ===== my/repo 12:0:r,y,z > 10:3:c
      #
      summarize_similar_repos "$repo" "$RET"
      echo "$RET"
    fi


    #
    # save tempdata to global data
    #
    ls "${TEMPLINEDATA}" | while read label ; do
      cat "${TEMPLINEDATA}/${label}" >> "${TEMPDATA}/${label}"
    done

  done < "${TEMPDIR}/abstractrepos"
}

############################################################
# update_list
############################################################
update_list() {
  #
  # only update the list if we have a full list,
  # all attached devices and no target repo filtering.
  #
  #
  # After running rg, we've likely modified the list, so if we
  # have not synched and reported the entire list, we'll
  # purge the saved .latest
  #
  if [ -r "${DATADIR}/.latest" ]; then
    mv "${DATADIR}/.latest" "${DATADIR}/.stale"
  fi

  #
  # if partial synch, then we return without
  # overwriting any of the full data samples
  #
  if [ "_$TARGET_REPO" != "_" ]; then
     return;
  fi

  #
  # move the new temp data, overwriting only files (devices)
  # that have been recently updated, if there are any at all
  #
  if [ `ls "${TEMPDATA}"|wc -l` != "0" ]; then
    mv -f "${TEMPDATA}"/* "${DATADIR}"
  fi
}

############################################################
# list_global
############################################################
list_global() {
  #
  # After running rg, we've likely modified the list, so if we
  # have not synched and reported the entire list, we'll
  # purge the saved .latest
  #
  if [ -r "${DATADIR}/.latest" ]; then
    cat "${DATADIR}/.latest"
    return
  fi

  # otherwise, we'll build a new .latest and print it
  TEMPLINE=${TEMPDIR}/line
  #
  # cleanup the comparisons
  #
  rm -rf "${TEMPDIR}"/*

  # 0000013:0000007:alice:foo/bar
  cut -d: -f3 "${DATADIR}"/* | sort | uniq > \
      "${TEMPDIR}/labels"

  cut -d: -f4 "${DATADIR}"/* | sort | uniq > \
      "${TEMPDIR}/abstractrepos"

  while read repo; do
    if [ -d "${TEMPLINE}" ]; then
         rm -rf "${TEMPLINE}"/*
    else mkdir -p "${TEMPLINE}"
    fi

    summarize_precomputed_repos "$repo"
    echo "$RET" | tee -a "${DATADIR}/.latest"

  done < "${TEMPDIR}/abstractrepos"
}

############################################################
# cleanup
############################################################
cleanup() {
  rm -rf "${TEMPDIR}"
}

############################################################
# main
############################################################
main() {
  initialize
  if [ "_$TEST" = "_YES" ]; then
    parse_target_test
  elif [ "_$LIST" = "_YES" ]; then
    list_global
  else
    normalize_target
    search_for_repos
    abstract_data
    label_devices
    compare_repos
    update_list
  fi
  cleanup
}

main
