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

  echo "Installing gomplate... "
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
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/nginx" ./template/nginx
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/mtg" ./template/mtg
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/xray" ./template/xray


##########################  SETTING UP SERVICES  ###########################

echo "${nl}${bold}Setting up services${reset}"

DEFAULT_OWNERSHIP=0:0
DEFAULT_FILE_PERMISSIONS=0440   # Readable by owner and group
DEFAULT_DIR_PERMISSIONS=0550    # Accessible by owner and group

install_file() {
  local path="$1"
  local ownership="${2:-$DEFAULT_OWNERSHIP}"
  local permissions="${3:-$DEFAULT_FILE_PERMISSIONS}"

  install -m $permissions /dev/null "$path"
  chown $ownership "$path"
}

install_dir() {
  local path="$1"
  local ownership="${2:-$DEFAULT_OWNERSHIP}"
  local permissions="${3:-$DEFAULT_DIR_PERMISSIONS}"

  install -m $permissions -d "$path"
  chown $ownership "$path"
}

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
    NEXTHOP_SOCKS_PROXY='socks5://172.22.0.11:1080'
    echo "${blue}Provide user ID (secret) from the netxhop xray:${reset}"
    read NEXTHOP_XRAY_USER
  fi

  install_file .gomplate.yaml
  install_file .params.yaml
  install_file .log.yaml
  install_file .env

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

  TELEGRAM_SECRET=$(gomplate --in '{{ .local.telegram.secret }}')
  TELEGRAM_SNI=$(echo "$TELEGRAM_SECRET" | base64url_to_base64 | base64 -d | dd bs=1 skip=17 2>/dev/null)

  > .params.yaml cat << EOF
nexthop:
  socks_proxy: ${NEXTHOP_SOCKS_PROXY:-''}
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

fi

[ -d ./config ] && rm -rf ./config
install_dir ./config


########## Preparing nginx configuration ##########

install_dir ./config/nginx
install_file ./config/nginx/nginx.conf

cat ./template/nginx/nginx.conf | gomplate > ./config/nginx/nginx.conf


########### Preparing Xray configuration ############

install_dir ./config/xray 65532:65532   # xray image user and group

gomplate --input-dir ./template/xray/config --output-dir ./config/xray
if [ -n "$(gomplate -i '{{ .nexthop }}')" ]; then
  gomplate --input-dir ./template/xray/config-nexthop --output-dir ./config/xray
fi


############ Preparing MTG configuration ############

install_dir ./config/mtg
install_file ./config/mtg/config.toml

cat ./template/mtg/config.toml | gomplate > ./config/mtg/config.toml


################# All configs ready #################

echo "${nl}${bold}All service configs ready:${reset}"
tree -a --dirsfirst $PWD/config


###########################  STARTING SERVICES  ############################

echo "${nl}${bold}Starting up services:${reset}"
docker compose up --detach
docker compose restart


##########################  ISSUING CERTIFICATES  ##########################

echo "${nl}${bold}Issuing certificates:${reset}"

echo "${green}Registering account:${reset}"
email="$( echo 'admin@{{ index .local.xray.xhttp.domains 0 }}' |  gomplate )"
docker exec acme.sh --register-account --server letsencrypt -m "$email"

domains=$( gomplate << 'EOF'
  {{ join .local.xray.reality.domains " " }}
  {{ join .local.xray.xhttp.domains " " }}
  {{ .params.telegram.domain }}
EOF
)

for domain in $domains; do
  echo "${green}Issuing certificate for $domain:${reset}"
  docker exec acme.sh --issue --server letsencrypt --standalone -d $domain \
                      --fullchain-file /certs/$domain.crt --key-file /certs/$domain.key \
                      --reloadcmd 'chown 101:101 /certs/*' || : # already issued certificates provoke error here
                                  #nginx user and group
done
