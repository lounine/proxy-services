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

services_files='/usr/local/share/proxy_services'
install -m 0755 -d "$services_files"


#######################  INSTALLING SYSTEM PACKAGES  #######################

if [ ! -f "$services_files"/system_packages_installed ]; then
  echo "${nl}${bold}Installing system packages:${reset}"

  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg apache2-utils tree

  echo "Installing gomplate:"
  curl -o /usr/local/bin/gomplate -#L \
       https://github.com/hairyhenderson/gomplate/releases/latest/download/gomplate_linux-${ARCH}
  chmod 755 /usr/local/bin/gomplate

  touch "$services_files"/system_packages_installed
fi


###########################  INSTALLING DOCKER  ############################

if [ ! -f "$services_files"/docker_installed ]; then
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

  touch "$services_files"/docker_installed
fi


##########################  SETTING UP SERVICES  ###########################

echo "${nl}${bold}Setting up services:${reset}"

DEFAULT_OWNERSHIP=1000:1000     # Owned and accessed by eventual container mock user
DEFAULT_PERMISSIONS=0440        # Readable by owner and group

create_secret_file() {
  local file="$1"
  local ownership="${2:-$DEFAULT_OWNERSHIP}"
  local permissions="${3:-$DEFAULT_PERMISSIONS}"
  local owner="${ownership%:*}"
  local group="${ownership#*:}"

  install -m "$permissions" -o "$owner" -g "$group" /dev/null "$file"
}

mtg_files="$services_files/mtg"
install -m 0755 -d "$mtg_files"


if [ ! -f "$services_files/settings.url" ]; then
  create_secret_file "$services_files/settings.url"

  echo "${bold}Provide settings file url:${reset}"
  read SETTINGS_URL

  echo -n ${SETTINGS_URL} > "$services_files/settings.url"
fi

context=settings="$(cat "$services_files/settings.url")"

create_secret_file "$mtg_files/config.toml"
cat "$DIR/mtg/config.toml" | gomplate -c "$context" > "$mtg_files/config.toml"

echo "${nl}${bold}All secrets have been set up. Current file structure:${reset}"
tree -a --dirsfirst $services_files


###########################  STARTING SERVICES  ############################

echo "${nl}${bold}Starting up services:${reset}"

docker compose --file "$DIR/compose.yml" up --detach
