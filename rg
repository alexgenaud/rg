#!/bin/bash

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


runtime_error() {
  echo error: $1
  exit 1
}

get_arg() {
  if [ $# -ne 1 ]; then runtime_error "get_arg wrong arg num"; fi
  if [ `echo "${1}_"|sed "s:^\(.\).*:\1:g"` = "-" ]; then
    if [ `echo "$1"|grep v|wc -l` = "1" ]; then VERBOSE=YES ; fi
    if [ `echo "$1"|grep l|wc -l` = "1" ]; then LIST=YES    ; fi
  elif [ "$ARG1" = "NO" ]; then ARG1="$1"
  elif [ "$ARG2" = "NO" ]; then ARG2="$1"
  elif [ "$ARG3" = "NO" ]; then ARG3="$1"
  fi
}

initialize() {
  VERBOSE=NO
  LIST=NO
  ARG1=NO
  ARG2=NO
  ARG3=NO
  DATADIR="${HOME}/.rg/data"
  TEMPDIR="${HOME}/.rg/tmp/$$"

  if [ $# -ge 1 ]; then get_arg "$1" ; fi
  if [ $# -ge 2 ]; then get_arg "$2" ; fi
  if [ $# -ge 3 ]; then get_arg "$3" ; fi
  if [ $# -ge 4 ]; then get_arg "$4" ; fi

  mkdir -p "${DATADIR}"
  mkdir -p "${TEMPDIR}/data"
}

search_repos() {
  find / -type d -name "*.git" \
       2> /dev/null \
       | sed "s:/*.git$::" | sort \
       1> "${TEMPDIR}/allrepos" \
       2> /dev/null
}

abstract_data() {
  # get devices
  grep "^/\(home\|cygdrive/[a-z]\|media/[^/]*\|mnt/[^/]*\)/.*"\
       "${TEMPDIR}/allrepos" |\
       sed "s:^/\(home\|[cm][a-z]*/[^/]*\)/\(.*\)$:/\1:" |\
       sort | uniq 1> "${TEMPDIR}/devices"

  grep "^/\(home\|cygdrive/[a-z]\|media/[^/]*\|mnt/[^/]*\)/.*"\
       "${TEMPDIR}/allrepos" |\
       sed "s:^/\(home\|[cm][a-z]*/[^/]*\)/\(.*\)$:\2:" |\
       sort | uniq 1> "${TEMPDIR}/abstractrepos"
}

label_devices() {
  while read device; do
    LABEL=
    if [ "_$device" = "_/home" -a `echo _$HOSTNAME|wc -c` -ge 3 ]; then
      echo "${HOSTNAME}:${device}" >> "${TEMPDIR}/labels"
    elif [ "_`echo $device|grep ^/cygdrive/[a-z]$|wc -l`" = "_1" ]; then
      if [ -r ${device}/.label ]; then
        LABEL=`head -1 ${device}/.label|\
             sed "s:^\([a-zA-Z0-9][a-zA-Z0-9]*\).*$:\1:"|\
             grep "^[a-zA-Z0-9][a-zA-Z0-9]*$"`
      fi
      if [ "_$LABEL" = "_" ]; then
        LABEL=`echo $device|\
             sed "s:^/[^/]*/\([a-z]\)$:\1:"|\
             tr '[:lower:]' '[:upper:]'`
      fi
      echo "${LABEL}:${device}" >> "${TEMPDIR}/labels"
    elif [ "_`echo $device |\
           grep "^/\(media\|mnt\)/[^/][^/]*$"|\
           wc -l`" = "_1" ]; then
      if [ -r ${device}/.label ]; then
        LABEL=`head -1 ${device}/.label|\
             sed "s:^\([a-zA-Z0-9][a-zA-Z0-9]*\).*$:\1:"|\
             grep "^[a-zA-Z0-9][a-zA-Z0-9]*$"`
      fi
      if [ "_$LABEL" = "_" ]; then
        LABEL=`echo $device|sed "s:^/[^/]*/\([^/]*\)$:\1:"`
      fi
      echo "${LABEL}:${device}" >> "${TEMPDIR}/labels"
    fi
  done < "${TEMPDIR}/devices"
}

_digits7() {
  RET=`echo 0000000$1|sed "s:^.*\(.......\)$:\1:"`
}


summarize_repo() {
  FULLPATH=$1
  TYPE=$2
  ABSTRACT=$3
  LABEL=$4
  ORIGDIR="$PWD"
  cd "${FULLPATH}"
  
  # number of git log entries
  git log --oneline --graph  > "${TEMPDIR}/log"
  NUMLOG=`wc -l "${TEMPDIR}/log" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
  _digits7 $NUMLOG
  NUMLOG=$RET

  # latest hash code
  LOGHASH=`head -1 "${TEMPDIR}/log"|sed "s:^[^a-f0-9]*\([a-f0-9]*\) \(.*\)$:\1:"`

  # latest log message
  LOGTEXT=`head -1 "${TEMPDIR}/log"|sed "s:^[^a-f0-9]*\([a-f0-9]*\) \(.*\)$:\2:"`

  # number of unclean changes (modified, delete, untracked)
  NUMSTAT=0000000
  if [ "_$TYPE" = "_WORK" ]; then
    git status --short > "${TEMPDIR}/status"
    NUMSTAT=`wc -l "${TEMPDIR}/status" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
    _digits7 $NUMSTAT
    NUMSTAT=$RET
  fi

  # return to original directory
  cd "${ORIGDIR}"

  # return array
  # example alex/cool:0000013:0000007:a1bc13d:alice:Bug fixes
  RET="${ABSTRACT}:${NUMLOG}:${NUMSTAT}:${LOGHASH}:${LABEL}:${TYPE}:${LOGTEXT}"
}

compare_repos() {
  SYNC=NO
  SAVE=NO
  PRINT=YES

  TEMPLINE=${TEMPDIR}/tmprepo
  while read repo; do

    #
    # test only 'rg' repos
    #
    if [ "_`echo $repo|grep rg|wc -l`" != "_1" ]; then continue; fi


    if [ -d "${TEMPLINE}" ]; then
      rm -rf "${TEMPLINE}"/*
    else
      mkdir -p "${TEMPLINE}"
    fi

    ABBREV_LINE=""

    while read dev; do
      LABEL=`echo $dev|cut -d: -f1`
      DEVICE=`echo $dev|cut -d: -f2`
      ABBREV=`echo $LABEL|sed "s:^\(.\).*:\1:"`
      FULLPATH=
      TYPE=
      if [ -d "${DEVICE}/${repo}" ]; then
        FULLPATH="${DEVICE}/${repo}"
        TYPE=WORK
        ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
      elif [ -d "${DEVICE}/${repo}.git" ]; then
        FULLPATH="${DEVICE}/${repo}.git"
        TYPE=BARE
        ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
      else
        # this device does not have this repository
        # add a blank space to the abbreviation line
        ABBREV_LINE="${ABBREV_LINE} "
        continue
      fi

      summarize_repo "$FULLPATH" "$TYPE" "$repo" "$LABEL"
      #echo loulou  RET is $RET
      # alex/cool:0000013:0000007:a1bc13d:alice

      NUMLOG=`echo $RET|cut -d: -f2`
      NUMSTAT=`echo $RET|cut -d: -f3`
      HASH=`echo $RET|cut -d: -f4`
      RANK="${TEMPLINE}/rank${NUMLOG}_${HASH}_${NUMSTAT}"
      if [ -r "$RANK" ]; then
        echo `head -1 "$RANK"`,$ABBREV > "$RANK"
      else
        NUMLOG=`echo $NUMLOG|sed "s:^0*::"`
        if [ "_$NUMLOG" = "_" ]; then NUMLOG=0; fi
        NUMSTAT=`echo $NUMSTAT|sed "s:^0*::"`
        if [ "_$NUMSTAT" = "_" ]; then NUMSTAT=0; fi
        echo "${NUMLOG}:${NUMSTAT}:${ABBREV}" > "$RANK"
      fi

    done < "${TEMPDIR}/labels"

    FIRST=YES
    LINE="${ABBREV_LINE}"
    for file in `ls "${TEMPLINE}"/rank*|sort -r`; do
      FILE=`cat "$file"`
      if [ "$FIRST" = "YES" ]; then
        LINE="${LINE} ${repo} ${FILE}"
        FIRST=NO
      else
        LINE="${LINE} > ${FILE}"
      fi
    done
    echo "$LINE"

     #
     # Summary
     #########
     # alex/cool:0000013:0000007:a1bc13d:alice
     # alex/cool:0000013:0000003:a1bc13d:frank
     # alex/cool:0000012:0000000:dfac12f:bob
     # alex/cool:0000012:0000000:dfac12d:eve
     # alex/cool:0000011:0000004:ce2c11a:dave
     # alex/cool:0000011:0000000:ce2c11a:dave


     #
     # Output
     #########
     # a b c d e f alex/cool 13:7:a > 13:3:f > 12:0:b,e > 11:4:d > 11:0:c
     # Synchronize alex/cool 13:7:a > 13:3:f > 13:0:b,c,e > 11:4:d

   
  done < "${TEMPDIR}/abstractrepos"
}

cleanup() {
  echo rm -rf "${TEMPDIR}"
}

main() {
  initialize
  search_repos
  abstract_data
  label_devices
  compare_repos
return
  cleanup
}

main
exit

get_device_and_user() {
  RET_TYPE=NO
  RET_DEVICE=NO
  RET_LABEL=NO
  RET_USER=NO
  RET_BASE=NO
  if [ $# -ne 1 ]; then runtime_error "get_device_and_user wrong arg num"; fi

  if   [ `echo "_$1"|sed "s:^_/\(home\)/..*:\1:"\
       |grep ^home$    |wc -l` = "1" ]; then
    ROOT=/home
  elif [ `echo "_$1"|sed "s:^_/\(cygdrive\)/..*:\1:"\
       |grep ^cygdrive$|wc -l` = "1" ]; then
    ROOT=/cygdrive
  elif [ `echo "_$1"|sed "s:^_/\(mnt\)/..*:\1:"\
       |grep ^mnt$     |wc -l` = "1" ]; then
    ROOT=/mnt
  elif [ `echo "_$1"|sed "s:^_/\(media\)/..*:\1:"\
       |grep ^media$   |wc -l` = "1" ]; then
    ROOT=/media
  else
    return
  fi
  POSTROOT=`echo "$1"|sed "s:^/\(home\|cygdrive\|mnt\|media\)/\(.*\)$:\2:"`

  RET_TYPE=EXTERNAL
  if [ "$ROOT" = "/home" ]; then
    RET_DEVICE=$ROOT
    RET_TYPE=INTERNAL
    if [ `echo _$HOSTNAME|wc -c` -ge 3 ]; then
      RET_LABEL=$HOSTNAME
    fi
    if [ `echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"|wc -c` -gt 2 ]; then
      RET_USER=`echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"`
    fi
  elif [ "$ROOT" = "/cygdrive" ]; then
    if [ `echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"|wc -c` -gt 1 ]; then
      RET_DEVICE=${ROOT}/`echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"`
      if [ -r "${RET_DEVICE}/.label" ]; then
        TST=`head -1 "${RET_DEVICE}/.label"|sed "s:^\([a-zA-Z][a-zA-Z0-9]*\).*$:\1:"`
        if [ `echo "_$TST"|wc -c` -gt 1 ]; then
          RET_LABEL=$TST
        fi
      fi
      if [ `echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"|wc -c` -ge 2 ]; then
        RET_USER=`echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"`
      fi
    fi 
  elif [ "$ROOT" = "/mnt" -o "$ROOT" = "/media" ]; then
    if [ `echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"|wc -c` -gt 1 ]; then
      RET_LABEL=`echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"`
      RET_DEVICE=${ROOT}/${RET_LABEL}
      if [ -r "${RET_DEVICE}/.label" ]; then
        TST=`head -1 "${RET_DEVICE}/.label"|sed "s:^\([a-zA-Z][a-zA-Z0-9]*\).*$:\1:"`
        if [ `echo "_$TST"|wc -c` -gt 1 ]; then
          RET_LABEL=$TST
        fi
      fi
      if [ `echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"|wc -c` -ge 2 ]; then
        RET_USER=`echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"`
      fi
    fi
  fi
  if [ "$RET_DEVICE" != "NO" -a "$RET_USER" != "NO" ]; then
    RET_BASE="${RET_DEVICE}/${RET_USER}"
  fi
}



BASEDIR="${PWD}"
if [ "$COMPARE" = "NO" ]; then
  get_device_and_user "$BASEDIR"
  
  #
  # check if we can meaningfully record this tree,
  # does it have a device and name, such as /media/device/name/...
  # or /home/name/...
  #
  if [ "$RET_DEVICE" = "NO" -o "$RET_USER"  = "NO" \
    -o "$RET_LABEL"  = "NO" -o "$RET_BASE"  = "NO" ]; then
    SAVE=NO
  else
    SAVE=YES
    mkdir -p "${HOME}/.rg/data"
    TEMPDIR="${HOME}/.rg/tmp$$"
    mkdir -p "${TEMPDIR}"
    SAVEOUT="${TEMPDIR}/${RET_LABEL}"
  fi

  for GITDIR in `find * .[a-zA-Z0-9]* -name "*.git"|sed "s:/.git$::"|sort|uniq`;do
    record_and_print_repo "${BASEDIR}/${GITDIR}" $SAVE $VERBOSE "$RET_DEVICE" "$SAVEOUT" "$TEMPDIR" 
  done
fi
exit
#
# rg : recursive git synchronization
#
# calls 'rgc' comparing /home/user
#        to any /media/device/user
#
rg() {
 if [ "${USERNAME}" = "" ]; then USERNAME=$USER
 fi
 if [ "${USERNAME}" = "" ]; then return; fi
 for m in `find /media/*/${USERNAME} /cygdrive/*/${USERNAME} \
     -maxdepth 0 -mindepth 0 -type d`; do
  rgc "${HOME}" "${m}"
 done 2> /dev/null
}

