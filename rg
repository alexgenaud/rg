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

get_device_and_user() {
  RET_TYPE=NO
  RET_DEVICE=NO
  RET_LABEL=NO
  RET_USER=NO
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
    RET_TYPE=INTERNAL
    if [ `echo _$HOSTNAME|wc -c` -ge 3 ]; then
      RET_DEVICE=$HOSTNAME
      RET_LABEL=$HOSTNAME
    fi
    if [ `echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"|wc -c` -gt 2 ]; then
      RET_USER=`echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"`
    fi
  else
    if [ `echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"|wc -c` -gt 1 ]; then
      RET_DEVICE=`echo "$POSTROOT"|sed "s:^\([^/]*\).*:\1:"`
      if [ -r "${ROOT}/${RET_DEVICE}/.label" ]; then
        TST=`head -1 "${ROOT}/${RET_DEVICE}/.label"|sed "s:^\([a-zA-Z][a-zA-Z0-9]*\).*$:\1:"`
        if [ `echo "_$TST"|wc -c` -gt 1 ]; then
          RET_LABEL=$TST
        fi
      fi
      if [ "$RET_LABEL" = "NO" -a "$ROOT" != "/cygdrive" ]; then
        RET_LABEL=RET_DEVICE
      fi
      if [ `echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"|wc -c` -ge 2 ]; then
        RET_USER=`echo "$POSTROOT"|sed "s:^[^/]*/\([^/]*\).*:\1:"`
      fi
    fi
  fi
}

get_device_and_user /cygdrive/g/alex
  echo RET_TYPE=$RET_TYPE
  echo RET_DEVICE=$RET_DEVICE
  echo RET_LABEL=$RET_LABEL
  echo RET_USER=$RET_USER
get_device_and_user /home/alex
  echo RET_TYPE=$RET_TYPE
  echo RET_DEVICE=$RET_DEVICE
  echo RET_LABEL=$RET_LABEL
  echo RET_USER=$RET_USER

exit

get_arg() {
  if [ $# -ne 1 ]; then runtime_error "get_arg wrong arg num"; fi
  if [ `echo "${1}_"|sed "s:^\(.\).*:\1:g"` = "-" ]; then
    if [ `echo "$1"|grep v|wc -l` = "1" ]; then VERBOSE=YES ; fi
    if [ `echo "$1"|grep c|wc -l` = "1" ]; then COMPARE=YES ; fi
    if [ `echo "$1"|grep l|wc -l` = "1" ]; then LIST=YES    ; fi
  elif [ "$ARG1" = "NO" ]; then ARG1="$1"
  elif [ "$ARG2" = "NO" ]; then ARG2="$1"
  elif [ "$ARG3" = "NO" ]; then ARG3="$1"
   echo gool
  fi
}

if [ $# -ge 1 ]; then get_arg "$1" ; fi
if [ $# -ge 2 ]; then get_arg "$2" ; fi
if [ $# -ge 3 ]; then get_arg "$3" ; fi
if [ $# -ge 4 ]; then get_arg "$4" ; fi
if [ $# -ge 5 ]; then get_arg "$5" ; fi
if [ $# -ge 6 ]; then get_arg "$6" ; fi
if [ $# -ge 7 ]; then get_arg "$7" ; fi
if [ $# -ge 8 ]; then get_arg "$8" ; fi
if [ $# -ge 9 ]; then get_arg "$9" ; fi

echo VERBOSE=$VERBOSE
echo COMPARE=$COMPARE
echo LIST=$LIST
echo ARG1=$ARG1
echo ARG2=$ARG2
echo ARG3=$ARG3


if [ "$COMPARE" = "NO" ]; then
  find * -type d -name "*.git"
fi

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

