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
get_arg() {
  if [ `echo "${1}_"|sed "s:^\(.\).*:\1:g"` = "-" ]; then
    if [ `echo "$1"|grep d|wc -l` = "1" ]; then DRYRUN=YES  ; fi
    if [ `echo "$1"|grep v|wc -l` = "1" ]; then VERBOSE=YES ; fi
    if [ `echo "$1"|grep l|wc -l` = "1" ]; then LIST=YES    ; fi
    if [ `echo "$1"|grep q|wc -l` = "1" ]; then QUIET=YES   ; fi
  elif [ "$ARG1" = "NO" ]; then ARG1="$1"
  elif [ "$ARG2" = "NO" ]; then ARG2="$1"
  elif [ "$ARG3" = "NO" ]; then ARG3="$1"
  fi
}

DRYRUN=NO
VERBOSE=NO
QUIET=NO
LIST=NO
ARG1=NO
ARG2=NO
ARG3=NO

if [ $# -ge 1 ]; then get_arg "$1" ; fi
if [ $# -ge 2 ]; then get_arg "$2" ; fi
if [ $# -ge 3 ]; then get_arg "$3" ; fi
if [ $# -ge 4 ]; then get_arg "$4" ; fi

initialize() {
  DATADIR="${HOME}/.rg/data"
  TEMPDIR="${HOME}/.rg/tmp/$$"
  TEMPDATA="${TEMPDIR}/data"
  mkdir -p "${DATADIR}"
  mkdir -p "${TEMPDATA}"
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
  sort "${TEMPDIR}/labels" | uniq > "${TEMPDIR}/tmp" 
  mv "${TEMPDIR}/tmp" "${TEMPDIR}/labels"
}

_digits7() {
  RET=`echo 0000000$1|sed "s:^.*\(.......\)$:\1:"`
}


summarize_one_repo() {
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

summarize_similar_repos() {
  repo="$1"
  SHOWSYNC="$2"

  ABBREV_LINE=""

  #
  # for each label:device
  #
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

    summarize_one_repo "$FULLPATH" "$TYPE" "$repo" "$LABEL"
    echo "$RET" > "${TEMPLINEDATA}/${LABEL}"
    # alex/cool:0000013:0000007:a1bc13d:alice

    NUMLOG=`echo $RET|cut -d: -f2`
    NUMSTAT=`echo $RET|cut -d: -f3`
    HASH=`echo $RET|cut -d: -f4`
    echo "${NUMLOG}:${NUMSTAT}:${TYPE}:${FULLPATH}" >> "${TEMPLINE}/rankindiv"

    RANKFILE="${TEMPLINE}/rankabbrev${NUMLOG}_${HASH}_${NUMSTAT}"
    if [ -r "$RANKFILE" ]; then
      echo `head -1 "$RANKFILE"`,$ABBREV > "$RANKFILE"
    else
      NUMLOG=`echo $NUMLOG|sed "s:^0*::"`
      if [ "_$NUMLOG" = "_" ]; then NUMLOG=0; fi
      NUMSTAT=`echo $NUMSTAT|sed "s:^0*::"`
      if [ "_$NUMSTAT" = "_" ]; then NUMSTAT=0; fi
      echo "${NUMLOG}:${NUMSTAT}:${ABBREV}" > "$RANKFILE"
    fi

  done < "${TEMPDIR}/labels"

  FIRST=YES
  RET="${ABBREV_LINE}"
  if [ "_$SHOWSYNC" = "_SYNC" ]; then
    RET=`echo $RET|sed "s:.:=:g"`
  fi
  for file in `ls "${TEMPLINE}"/rankabbrev*|sort -r`; do
    FILE=`cat "$file"`
    if [ "$FIRST" = "YES" ]; then
      RET="${RET} ${repo} ${FILE}"
      FIRST=NO
    else
      RET="${RET} > ${FILE}"
    fi
  done

  # return RET
}

summarize_precomputed_repos() {
  repo="$1"

  ABBREV_LINE=""

  #
  # for each label
  #
  while read dev; do
    LABEL=`echo $dev|cut -d: -f1`
    ABBREV=`echo $LABEL|sed "s:^\(.\).*:\1:"`
    
    #bin.bak.work:0000004:0000000:21dc865:ARCH_201311:WORK:search, index, label, not yet compare
    LINE=`grep "^${repo}:" "${DATADIR}/$LABEL"`

    if [ "_`echo $LINE|wc -c`" != "_1" ]; then
      ABBREV_LINE="${ABBREV_LINE}${ABBREV}"
    else
      # add a blank space to the abbreviation line
      ABBREV_LINE="${ABBREV_LINE} "
      continue
    fi

    NUMLOG=`echo $LINE|cut -d: -f2`
    NUMSTAT=`echo $LINE|cut -d: -f3`
    HASH=`echo $LINE|cut -d: -f4`

    RANKFILE="${TEMPLINE}/rankabbrev${NUMLOG}_${HASH}_${NUMSTAT}"
    if [ -r "$RANKFILE" ]; then
      echo `head -1 "$RANKFILE"`,$ABBREV > "$RANKFILE"
    else
      NUMLOG=`echo $NUMLOG|sed "s:^0*::"`
      if [ "_$NUMLOG" = "_" ]; then NUMLOG=0; fi
      NUMSTAT=`echo $NUMSTAT|sed "s:^0*::"`
      if [ "_$NUMSTAT" = "_" ]; then NUMSTAT=0; fi
      echo "${NUMLOG}:${NUMSTAT}:${ABBREV}" > "$RANKFILE"
    fi

  done < "${TEMPDIR}/labels"

  FIRST=YES
  RET="${ABBREV_LINE}"
  for file in `ls "${TEMPLINE}"/rankabbrev*|sort -r`; do
    FILE=`cat "$file"`
    if [ "$FIRST" = "YES" ]; then
      RET="${RET} ${repo} ${FILE}"
      FIRST=NO
    else
      RET="${RET} > ${FILE}"
    fi
  done

  # return RET
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
  sort -r "${TEMPLINE}/rankindiv" > "${TEMPLINE}/sort"
  while read RANK; do
    LOGNUM=`echo $RANK|cut -d: -f1|sed "s:^0*::"`
    if [ "_$LOGNUM" = "_" ]; then LOGNUM=0; fi

    STATNUM=`echo $RANK|cut -d: -f2|sed "s:^0*::"`
    if [ "_$STATNUM" = "_" ]; then STATNUM=0; fi

    TYPE=`echo $RANK|cut -d: -f3`
    FULLPATH=`echo $RANK|cut -d: -f4`

    if [ "$LATEST" = "YES" ]; then
      LATEST_LOGNUM=$LOGNUM
      LATEST_TYPE=$TYPE
      LATEST_FULLPATH=$FULLPATH
      LATEST=NO
      continue
    elif [ "_$STATNUM" != "_0" \
      -o "_$LOGNUM" = "_$LATEST_LOGNUM" ]; then
      # can only fast forward a clean repo
      # and dont bother synching already synched
      continue
    elif [ "_$TYPE" = "_WORK" ]; then
      # then we have to pull
      cd "$FULLPATH"
      echo $FULLPATH pull from $LATEST_FULLPATH >> "${TEMPDIR}/gitstdout"
      if [ "_$DRYRUN" = "_YES" ]; then
        echo "    $FULLPATH" pull from "$LATEST_FULLPATH"
      else
        git pull "$LATEST_FULLPATH" master \
          1>> "${TEMPDIR}/gitstdout" 2>> "${TEMPDIR}/gitstderr"
      fi
      RET="SYNC"
    elif [ "_$TYPE" = "_BARE" ]; then
      # then we have to push
      cd "$LATEST_FULLPATH"
      echo $LATEST_FULLPATH push to $FULLPATH >> "${TEMPDIR}/gitstdout"
      if [ "_$DRYRUN" = "_YES" ]; then
        echo "    $LATEST_FULLPATH" push to "$FULLPATH"
      else
        git push "$FULLPATH" master \
          1>> "${TEMPDIR}/gitstdout" 2>> "${TEMPDIR}/gitstderr"
      fi
      RET="SYNC"
    fi
  done < "${TEMPLINE}/sort"
  cd "${SYNC_ORIGDIR}"
}

compare_repos() {
  VERBOSE=NO

  TEMPLINE=${TEMPDIR}/line
  TEMPLINEDATA=${TEMPDIR}/linedata
  while read repo; do

    #
    # test only 'rg' repos
    #
    #if [ "_`echo $repo|grep rg|wc -l`" != "_1" ]; then continue; fi


    if [ -d "${TEMPLINE}" ]; then
         rm -rf "${TEMPLINE}"/*
    else mkdir -p "${TEMPLINE}"
    fi

    if [ -d "${TEMPLINEDATA}" ]; then
         rm -rf "${TEMPLINEDATA}"/*
    else mkdir -p "${TEMPLINEDATA}"
    fi

    summarize_similar_repos "$repo" "NoSync"
    if [ "_$QUIET" = "_NO" ]; then echo "$RET"
    else PREVLINE=$RET
    fi

    synchronize_similar_repos "$repo"
    if [ "_$RET" = "_SYNC" ]; then
      if [ "_$QUIET" = "_YES" ]; then echo $PREVLINE ; fi
      rm -rf "${TEMPLINE}"/* "${TEMPLINEDATA}"/*
      summarize_similar_repos "$repo" "SYNC"
      echo "$RET"
    fi

    #
    # save tempdata to global data
    #
    for label in `ls "${TEMPLINEDATA}"`; do
      cat "${TEMPLINEDATA}/${label}" >> "${TEMPDATA}/${label}"
    done

  done < "${TEMPDIR}/abstractrepos"
}

update_list() {
  mv "${TEMPDATA}"/* "${DATADIR}"
}

list_global() {
  TEMPLINE=${TEMPDIR}/line
  #
  # cleanup the comparisons
  #
  rm -rf "${TEMPDIR}"/*

  cut -d: -f1 "${DATADIR}"/* | sort | uniq > \
      "${TEMPDIR}/abstractrepos"

  cut -d: -f5 "${DATADIR}"/* | sort | uniq > \
      "${TEMPDIR}/labels"

  while read repo; do
    if [ -d "${TEMPLINE}" ]; then
         rm -rf "${TEMPLINE}"/*
    else mkdir -p "${TEMPLINE}"
    fi

    summarize_precomputed_repos "$repo"
    echo "$RET"

  done < "${TEMPDIR}/abstractrepos"
}

cleanup() {
  rm -rf "${TEMPDIR}"
}

main() {
  initialize
  if [ "_$LIST" = "_YES" ]; then
    list_global
  else
    search_repos
    abstract_data
    label_devices
    compare_repos
    update_list
  fi
  cleanup
}

main
