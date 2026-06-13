#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/_common.sh

cd "$SCRIPT_DIR"/..


##########################  READING CLI OPTIONS  ###########################

usage() {
  cat <<EOF
Usage: ./setup.sh [--log-level|-l <level>] [--help|-h]

Options:
  --log-level, -l     Set the log level (default: warning)
                      supported: debug, info, warning, error, none
  --help, -h          Show this help

EOF
}

LOG_LEVEL=warning

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-level|-l)
      LOG_LEVEL="${2:-}"
      shift 2
      ;;
    --log-level=*)
      LOG_LEVEL="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done


##########################  SETTING UP SERVICES  ###########################

base64url_to_base64() {
  local base64=$(tr -- '-_' '+/')
  local reminder=$(( ${#base64} % 4 ))
  [ $reminder = 2 ] && base64="${base64}=="
  [ $reminder = 3 ] && base64="${base64}="
  echo -n "$base64"
}


################# Getting settings ##################

if [ ! -f .gomplate.yaml ]; then
  echo "${nl}${bold}Configuring services${reset}"

  echo "${blue}Provide config file url:${reset}"
  read LOCAL_CONFIG_URL

  echo "${blue}Provide users file url (leave blank to use config file):${reset}"
  read USERS_URL
  [ -n "$USERS_URL" ] || USERS_URL="$LOCAL_CONFIG_URL"

  echo "${blue}Provide config file url for netxhop xray (leave blank to skip):${reset}"
  read NEXTHOP_CONFIG_URL
  
  if [ -n "$NEXTHOP_CONFIG_URL" ]; then
    echo "${blue}Provide user ID (secret) from the netxhop xray:${reset}"
    read NEXTHOP_XRAY_USER
  fi

  install -m 640 /dev/null .gomplate.yaml
  install -m 640 /dev/null .params.yaml
  install -m 640 /dev/null .log.yaml
  install -m 640 /dev/null .env

  > .gomplate.yaml cat << EOF
missingKey: zero
context:
  local:
    url: $LOCAL_CONFIG_URL
  users:
    url: $USERS_URL
  nexthop:
    url: ${NEXTHOP_CONFIG_URL:-file:///dev/null}
  params:
    url: .params.yaml
  log:
    url: .log.yaml
EOF

fi

echo "${nl}${bold}Setting up services...${reset}"

TELEGRAM_SECRET=$(gomplate --in '{{ .local.telegram.secret }}')
TELEGRAM_SNI=$(echo "$TELEGRAM_SECRET" | base64url_to_base64 | base64 -d | dd bs=1 skip=17 2>/dev/null)

if [ -n "$(gomplate --in '{{ .nexthop }}')" ]; then
  NEXTHOP_SOCKS_PROXY='"socks5://xray:1080"'
  : ${NEXTHOP_XRAY_USER:=$(gomplate --in '{{ .params.nexthop.xray.user }}')}
fi

> .params.yaml cat << EOF
nexthop:
  socks_proxy: '${NEXTHOP_SOCKS_PROXY:-}'
  xray:
    user: ${NEXTHOP_XRAY_USER:-}
telegram:
  domain: ${TELEGRAM_SNI:-}
EOF

> .log.yaml cat << EOF
level: $LOG_LEVEL
EOF

> .env gomplate << EOF
{{ if has .local "port" }}EXTERNAL_PORT={{ .local.port }}{{ end }}
EOF


############### Finalizing templates ################

if [ -d ./tempate/xray/config ]; then
  mv ./tempate/xray/config/* ./tempate/xray/
  rm -rf ./tempate/xray/config
fi

if [ -d ./tempate/xray/config-nexthop ] && [ -n "$(gomplate -i '{{ .nexthop }}')" ]; then
  mv -f ./tempate/xray/config-nexthop/* ./tempate/xray/
  rm -rf ./tempate/xray/config-nexthops
fi


######### Rendrering configs from templates #########

[ -d ./config ] && rm -rf ./config
install -m 750 -d ./config

gomplate --input-dir ./template --output-dir ./config

chmod 750 ./config/*
chmod 640 ./config/*/*
sudo chown :65532 ./config/xray
sudo chown :65532 ./config/xray/*


################# All configs ready #################

echo "${nl}${bold}All service configs ready:${reset}"
tree -a --dirsfirst $PWD/config
