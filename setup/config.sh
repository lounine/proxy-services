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

echo "${nl}${bold}Setting up services${reset}"

base64url_to_base64() {
  local base64=$(tr -- '-_' '+/')
  local reminder=$(( ${#base64} % 4 ))
  [ $reminder = 2 ] && base64="${base64}=="
  [ $reminder = 3 ] && base64="${base64}="
  echo -n "$base64"
}


################# Getting settings ##################

if [ ! -f .gomplate.yaml ]; then
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

TELEGRAM_SECRET=$(gomplate --in '{{ .local.telegram.secret }}')
TELEGRAM_SNI=$(echo "$TELEGRAM_SECRET" | base64url_to_base64 | base64 -d | dd bs=1 skip=17 2>/dev/null)

if [ -n "$(gomplate --in '{{ .nexthop }}')" ]; then
  NEXTHOP_SOCKS_PROXY='"socks5://172.22.0.11:1080"'
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

[ -d ./config ] && rm -rf ./config
install -m 750 -d ./config


########## Preparing nginx configuration ##########

install -m 750 -d ./config/nginx
cat ./template/nginx/nginx.conf | gomplate > ./config/nginx/nginx.conf
chmod 640 ./config/nginx/nginx.conf


########### Preparing Xray configuration ############

install -m 750 -d ./config/xray;  

gomplate --input-dir ./template/xray/config --output-dir ./config/xray
if [ -n "$(gomplate -i '{{ .nexthop }}')" ]; then
  gomplate --input-dir ./template/xray/config-nexthop --output-dir ./config/xray
fi

# Ensure xray (group id 65532) can read config files and we still can write them:
sudo chown :65532 ./config/xray
sudo chown :65532 ./config/xray/*
chmod 640 ./config/xray/*


############ Preparing MTG configuration ############

install -m 750 -d ./config/mtg
cat ./template/mtg/config.toml | gomplate > ./config/mtg/config.toml
chmod 640 ./config/mtg/config.toml

################# All configs ready #################

echo "${nl}${bold}All service configs ready:${reset}"
tree -a --dirsfirst $PWD/config
