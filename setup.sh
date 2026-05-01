#!/usr/bin/env bash

set -eu

if [ "$TERM" != 'dumb' ] && [ "$TERM" != 'unknown' ]; then
  black=$(tput setaf 0); red=$(tput setaf 1); green=$(tput setaf 2); yellow=$(tput setaf 3); blue=$(tput setaf 4); magenta=$(tput setaf 5); cyan=$(tput setaf 6); white=$(tput setaf 7)
  bold=$(tput bold); ul=$(tput smul); reset=$(tput sgr 0)
  nl=$'\n'
fi

if [ $EUID -ne 0 ]; then
   echo "${bold}This script should be run with root privileges. Please use sudo.${reset}"
   exit 1
fi

ARCH=$(dpkg --print-architecture)
DIR="$( cd "$( dirname "$0" )" && pwd )"

[ -f "$DIR/.env" ] && source "$DIR/.env"

services_files='/usr/local/share/proxy_services'
install -m 0755 -d "$services_files"


#######################  INSTALLING SYSTEM PACKAGES  #######################

if [ ! -f "$services_files"/-system-packages-installed ]; then
  echo "${nl}${bold}Installing system packages:${reset}"

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg apache2-utils tree

  echo "Installing gomplate:"
  curl -o /usr/local/bin/gomplate -#L \
       https://github.com/hairyhenderson/gomplate/releases/latest/download/gomplate_linux-${ARCH}
  chmod 0755 /usr/local/bin/gomplate

  touch "$services_files"/-system-packages-installed
fi


###########################  INSTALLING DOCKER  ############################

if [ ! -f "$services_files"/-docker-installed ]; then
  echo "${nl}${bold}Installing Docker:${reset}"

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

  touch "$services_files"/-docker-installed
fi


##########################  SETTING UP SERVICES  ###########################

echo "${nl}${bold}Setting up services:${reset}"

DEFAULT_OWNER=1000              # Owned and accessed by eventual container mock user and group
DEFAULT_GROUP=1000              
DEFAULT_FILE_PERMISSIONS=0440   # Readable by owner and group
DEFAULT_DIR_PERMISSIONS=0550    # Accessible by owner and group

set_permissions() {
  local path="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local group="${3:-$DEFAULT_GROUP}"

  if [ -d "$path" ]; then
    find "$path" -type f -exec chown "$owner:$group" {} \;
    find "$path" -type f -exec chmod "$DEFAULT_FILE_PERMISSIONS" {} \;
  else
    chown "$owner:$group" "$path"
    chmod "$DEFAULT_FILE_PERMISSIONS" "$path"
  fi
}

install_dir() {
  local path="$1"
  local owner="${2:-$DEFAULT_OWNER}"
  local group="${3:-$DEFAULT_GROUP}"

  install -m $DEFAULT_DIR_PERMISSIONS -o $owner -g $group -d "$path"
}


################# Getting settings ##################

if [ ! -f "$services_files/settings.url" ]; then
  echo "${bold}Provide settings file url:${reset}"
  read SETTINGS_URL

  echo -n ${SETTINGS_URL} > "$services_files/settings.url"
  set_permissions "$services_files/settings.url" 0 0
fi

if [ ! -f "$services_files/users.url" ]; then
  echo "${bold}Provide users file url (leave blank to use settings file):${reset}"
  read USERS_URL

  if [ -n "$USERS_URL" ]; then
    echo -n ${USERS_URL} > "$services_files/users.url"
    set_permissions "$services_files/users.url" 0 0
  else
    cp "$services_files/settings.url" "$services_files/users.url"
  fi
fi

settings=settings="$(cat "$services_files/settings.url")"
users=users="$(cat "$services_files/users.url")"


########## Preparing HAProxy configuration ##########

haproxy_files="$services_files/haproxy"
[ -d "$haproxy_files" ] && rm -rf "$haproxy_files"
install_dir "$haproxy_files"

cat "$DIR/haproxy/haproxy.cfg" | gomplate -c "$settings" > "$haproxy_files/haproxy.cfg"
set_permissions "$haproxy_files/haproxy.cfg" 99 99    # haproxy user and group


########### Preparing Xray configuration ############

xray_files="$services_files/xray"
[ -d "$xray_files" ] && rm -rf "$xray_files"
install_dir "$xray_files"
install_dir "$xray_files/config"

gomplate -c "$settings" -c "$users" --input-dir "$DIR/xray/config" --output-dir "$xray_files/config"
set_permissions "$xray_files/config"


############ Preparing MTG configuration ############

mtg_files="$services_files/mtg"
[ -d "$mtg_files" ] && rm -rf "$mtg_files"
install_dir "$mtg_files"

cat "$DIR/mtg/config.toml" | gomplate -c "$settings" > "$mtg_files/config.toml"
set_permissions "$mtg_files/config.toml"


################# All configs ready #################

echo "${nl}${bold}All secrets have been set up. Current file structure:${reset}"
tree -a --dirsfirst $services_files

echo "${nl}${bold}Telegram proxy status:${reset}"
docker run --rm -v "$mtg_files/config.toml:/config/config.toml" \
  nineseconds/mtg:2 doctor /config/config.toml || : # Ignore errors


###########################  STARTING SERVICES  ############################

echo "${nl}${bold}Starting up services:${reset}"
docker compose --file "$DIR/compose.yml" up --detach
docker compose restart
