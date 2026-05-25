#!/usr/bin/env bash

set -eu

if [ "$TERM" != 'dumb' ] && [ "$TERM" != 'unknown' ]; then
  black=$(tput setaf 0); red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4); magenta=$(tput setaf 5); cyan=$(tput setaf 6); white=$(tput setaf 7)
  bold=$(tput bold); ul=$(tput smul); reset=$(tput sgr 0)
  nl=$'\n'
fi


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


####################  CHECKING / PREPARING ENVIRONMENT  ####################

if [ $EUID -ne 0 ]; then
  echo "${bold}This script should be run with root privileges. Please use sudo.${reset}"
  exit 1
fi

ARCH=$(dpkg --print-architecture)
DIR="$( cd "$( dirname "$0" )" && pwd )"

install -m 0755 -d '/usr/local/share/proxy_services'
cd '/usr/local/share/proxy_services'


#######################  INSTALLING SYSTEM PACKAGES  #######################

if [ ! -f .installed-system-packages ]; then
  echo "${nl}${bold}Installing system packages${reset}"

  apt-get update
  apt-get install -y --no-install-recommends \
    curl unzip ca-certificates gnupg apache2-utils tree

  echo "Installing gomplate:"
  curl -o /usr/local/bin/gomplate \
       -fsSL https://github.com/hairyhenderson/gomplate/releases/latest/download/gomplate_linux-${ARCH}
  chmod 0755 /usr/local/bin/gomplate

  touch .installed-system-packages
fi


###########################  INSTALLING DOCKER  ############################

if [ ! -f .installed-docker ]; then
  echo "${nl}${bold}Installing Docker${reset}"

  REPO='https://download.docker.com/linux/ubuntu'
  DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
  DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
  OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)

  install -m 0755 -d '/etc/apt/keyrings'

  if [ ! -f $DOCKER_GPG ]; then
    curl -fsSL $REPO/gpg | gpg --dearmor -o $DOCKER_GPG
    chmod a+r $DOCKER_GPG
  fi

  if [ ! -f $DOCKER_SOURCES ]; then
    > $DOCKER_SOURCES echo "deb [arch=$ARCH signed-by=$DOCKER_GPG] $REPO $OS_RELEASE stable"
  fi

  apt-get update

  if apt-cache policy docker-ce | grep -q "$REPO" ; then
    echo "${bold}Successfully set up repository, installing Docker...${reset}"
  else
    echo "${bold}${red}ERROR: Docker repository setup failed.${reset}"
    exit 1
  fi

  apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  touch .installed-docker
fi


##########################  DOWNLOADING CONFIGS  ###########################

echo "${nl}${bold}Downloading latest configs${reset}"

TEMP_DIR=$(mktemp -d)
[ -d "$TEMP_DIR" ] || { echo "Could not create temp dir"; exit 1; }
cleanup() { rm -rf "$TEMP_DIR"; };    trap cleanup EXIT

BRANCH_NAME='self-steal'
curl -o "$TEMP_DIR/sources.zip" \
     -fsSL https://github.com/lounine/proxy-services/archive/refs/heads/$BRANCH_NAME.zip
unzip -q "$TEMP_DIR/sources.zip" -d "$TEMP_DIR"
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/compose.yml" .
rm -rf ./template; install -m 0755 -d ./template
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/haproxy" ./template/haproxy
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/caddy" ./template/caddy
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/mtg" ./template/mtg
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/xray" ./template/xray


##########################  SETTING UP SERVICES  ###########################

DEFAULT_OWNER=1000              # Owned and accessed by eventual container mock user and group
DEFAULT_GROUP=1000              
DEFAULT_FILE_PERMISSIONS=0440   # Readable by owner and group
DEFAULT_DIR_PERMISSIONS=0550    # Accessible by owner and group

set_permissions() {
  local path="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local group="${3:-$DEFAULT_GROUP}"
  local permissions="${4:-$DEFAULT_FILE_PERMISSIONS}"

  if [ -d "$path" ]; then
    find "$path" -type f -exec chown "$owner:$group" {} \;
    find "$path" -type f -exec chmod "$permissions" {} \;
  else
    chown "$owner:$group" "$path"
    chmod "$permissions" "$path"
  fi
}

install_dir() {
  local path="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local group="${3:-$DEFAULT_GROUP}"
  local permissions="${4:-$DEFAULT_DIR_PERMISSIONS}"

  install -m $permissions -o $owner -g $group -d "$path"
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
    NEXTHOP_SOCKS_PROXY='socks5://xray:1080'
    echo "${blue}Provide user ID (secret) from the netxhop xray:${reset}"
    read NEXTHOP_XRAY_USER
  fi

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
  set_permissions .gomplate.yaml 0 0
fi

TELEGRAM_SECRET=$(gomplate --in '{{ .local.telegram.secret }}')
TELEGRAM_SNI=$(echo "$TELEGRAM_SECRET" | basenc -d --base64url 2>/dev/null | dd bs=1 skip=17 2>/dev/null)

> .params.yaml cat << EOF
nexthop:
  socks_proxy: ${NEXTHOP_SOCKS_PROXY:-''}
  xray:
    user: ${NEXTHOP_XRAY_USER:-}
telegram:
  domain: ${TELEGRAM_SNI:-}
EOF
set_permissions .params.yaml 0 0

> .log.yaml cat << EOF
level: $LOG_LEVEL
EOF
set_permissions .log.yaml 0 0

> .env gomplate << EOF
EXTERNAL_PORT={{ .local.port }}
EOF
set_permissions .env 0 0

echo "${nl}${bold}Setting up services${reset}"

rm -rf ./config; install -m 0755 -d ./config

########## Preparing HAProxy configuration ##########

[ -d ./config/haproxy ] && rm -rf ./config/haproxy
install_dir ./config/haproxy

> ./config/haproxy/haproxy.cfg gomplate < ./template/haproxy/haproxy.cfg
set_permissions ./config/haproxy/haproxy.cfg 99 99    # haproxy user and group


########### Preparing Caddy configuration ###########

[ -d ./config/caddy ] && rm -rf ./config/caddy
install_dir ./config/caddy

> ./config/caddy/Caddyfile gomplate < ./template/caddy/Caddyfile


########### Preparing Xray configuration ############

[ -d ./config/xray ] && rm -rf ./config/xray
install_dir ./config/xray
install_dir ./config/xray/config 65532 65532   # xray image user and group

gomplate --input-dir ./template/xray/config --output-dir ./config/xray/config
if [ -n "$(gomplate -i '{{ .nexthop }}')" ]; then
  gomplate --input-dir ./template/xray/config-nexthop --output-dir ./config/xray/config
fi
set_permissions ./config/xray/config 65532 65532   # xray image user and group


############ Preparing MTG configuration ############

[ -d ./config/mtg ] && rm -rf ./config/mtg
install_dir ./config/mtg

> ./config/mtg/config.toml gomplate < ./template/mtg/config.toml
set_permissions ./config/mtg/config.toml


################# All configs ready #################

echo "${nl}${bold}All service configs ready:${reset}"
tree -a --dirsfirst ./config


###########################  STARTING SERVICES  ############################

echo "${nl}${bold}Starting up services:${reset}"
docker compose up --detach
docker compose restart
