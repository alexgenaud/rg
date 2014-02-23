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
VERBOSE=NO
COMPARE=NO
LIST=NO
ARG1=NO
ARG2=NO
ARG3=NO


runtime_error() {
  echo error: $1
  exit 1
}

get_arg() {
  if [ $# -ne 1 ]; then runtime_error "get_arg wrong arg num"; fi
  if [ `echo "${1}_"|sed "s:^\(.\).*:\1:g"` = "-" ]; then
    if [ `echo "$1"|grep v|wc -l` = "1" ]; then VERBOSE=YES ; fi
    if [ `echo "$1"|grep c|wc -l` = "1" ]; then COMPARE=YES ; fi
    if [ `echo "$1"|grep l|wc -l` = "1" ]; then LIST=YES    ; fi
  elif [ "$ARG1" = "NO" ]; then ARG1="$1"
  elif [ "$ARG2" = "NO" ]; then ARG2="$1"
  elif [ "$ARG3" = "NO" ]; then ARG3="$1"
  fi
}

if [ $# -ge 1 ]; then get_arg "$1" ; fi
if [ $# -ge 2 ]; then get_arg "$2" ; fi
if [ $# -ge 3 ]; then get_arg "$3" ; fi
if [ $# -ge 4 ]; then get_arg "$4" ; fi

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


record_and_print_repo() {
  GITDIR=$1
  SAVE=$2
  VERBOSE=$3
  SAVEDEVICE=$4
  SAVEFILE=$5
  TEMPDIR=$6
  BASEDIR=${PWD}
  cd "$GITDIR"
  git log --oneline --graph  > "${TEMPDIR}/log"
  git status --short > "${TEMPDIR}/status"
  NUMLOG=`wc -l "${TEMPDIR}/log" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
  NUMSTAT=`wc -l "${TEMPDIR}/status" | sed "s:^[^0-9]*\([0-9]*\).*$:\1:"`
  LOGHASH=`head -1 "${TEMPDIR}/log"|sed "s:^[^a-f0-9]*\([a-f0-9]*\) \(.*\)$:\1:"`
  LOGTEXT=`head -1 "${TEMPDIR}/log"|sed "s:^[^a-f0-9]*\([a-f0-9]*\) \(.*\)$:\2:"`
  TRUCDIR=`echo "$GITDIR"|sed "s:^${SAVEDEVICE}/\(.*\)/*$:\1:"`
  if [ "$SAVE" = "YES" ]; then
    echo $TRUCDIR : $NUMLOG : $LOGHASH : $NUMSTAT : $LOGTEXT >> "$SAVEFILE"
  fi
  if [ "$NUMSTAT" != "0" -o "$VERBOSE" = "YES" ]; then
    echo $TRUCDIR : $NUMLOG : $LOGHASH : $NUMSTAT : $LOGTEXT
  fi
  cd "$BASEDIR"
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

