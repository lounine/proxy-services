#!/usr/bin/env bash

if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != 'dumb' ] && [ "$TERM" != 'unknown' ]; then
  black=$(tput setaf 0); red=$(tput setaf 1); green=$(tput setaf 2); 
  yellow=$(tput setaf 3); blue=$(tput setaf 4); magenta=$(tput setaf 5); 
  cyan=$(tput setaf 6); white=$(tput setaf 7)
  bold=$(tput bold); ul=$(tput smul); reset=$(tput sgr 0)
else
  black=''; red=''; green=''; yellow=''; blue=''; magenta=''; cyan=''; white=''
  bold=''; ul=''; reset=''
fi

nl=$'\n'
