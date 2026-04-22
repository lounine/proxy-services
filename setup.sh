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

DIR="$( cd "$( dirname "$0" )" && pwd )"

REPO='https://download.docker.com/linux/ubuntu'
DOCKER_GPG='/etc/apt/keyrings/docker.gpg'
DOCKER_SOURCES='/etc/apt/sources.list.d/docker.list'
ARCH=$(dpkg --print-architecture)
OS_RELEASE=$(. /etc/os-release && echo $VERSION_CODENAME)


#######################  INSTALLING SYSTEM PACKAGES  #######################

echo "${nl}${bold}Installing system packages:${reset}"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg apache2-utils tree


#######################  INSTALLING DOCKER  #######################

echo "${nl}${bold}Installing Docker:${reset}"

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


#######################  SETTING UP SECRETS  #######################

echo "${nl}${bold}Setting up secrets:${reset}"

DEFAULT_OWNERSHIP=1000:1000     # Owned and accessed by container mock user
DEFAULT_PERMISSIONS=0440        # Readable by owner and group

ensure_secret_file() {
  local file="$1"
  local ownership="${2:-$DEFAULT_OWNERSHIP}"
  local permissions="${3:-$DEFAULT_PERMISSIONS}"
  local owner="${ownership%:*}"
  local group="${ownership#*:}"

  [ -f "$file" ] || install -m "$permissions" -o "$owner" -g "$group" /dev/null "$file"
}

add_secret() {
  local content; read content
  ensure_secret_file "$@"
  local file="$1"

  echo "$content" >> "$file"
}

stripcolors() {
  sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
}


services_files='/usr/local/share/proxy_services'
install -m 0755 -d "$services_files"

tg_proxy_files="$services_files/tg_proxy"
install -m 0755 -d "$tg_proxy_files"

telego_files="$services_files/telego"
install -m 0755 -d "$telego_files"

if [ -f "$tg_proxy_files/secrets" ]; then
  echo "TG-Proxy secrets file already exists. Skipping generation."
else
  for run in {1..16}; do
    head -c 16 /dev/urandom | xxd -p | add_secret "$tg_proxy_files/secrets"
  done

  echo "${nl}${bold}Generated TG-Proxy secrets:${reset}"
  cat "$tg_proxy_files/secrets"
fi

ensure_secret_file "$tg_proxy_files/.env"
printf "SECRET=" > "$tg_proxy_files/.env"
cat "$tg_proxy_files/secrets" | tr '\n' ',' | sed 's/,$/\n/' >> "$tg_proxy_files/.env"


if [ -f "$telego_files/secrets" ]; then
  echo "Telego secrets file already exists. Skipping generation."
else
  for run in {1..16}; do
    secret_output=$(
      docker run -t --rm scratchnet/telego:v0.3 generate pkgs.alpinelinux.org |
      stripcolors
    )
    if [[ $secret_output =~ (^| )secret=([a-f0-9]*) ]]; then
      echo "user${run}=${BASH_REMATCH[2]}" | add_secret "$telego_files/secrets"
    else
      echo "${bold}${red}ERROR: Failed to generate a valid secret for Telego. Output:${reset}"
      echo "$secret_output"
      exit 1
    fi
  done

  echo "${nl}${bold}Generated Telego secrets:${reset}"
  cat "$telego_files/secrets"
fi

ensure_secret_file "$telego_files/config.toml"
secrets_content=$(cat "$telego_files/secrets")
cat "$DIR/telego_files/config.toml" | awk -v r="$secrets_content" '{gsub(/%SECRETS%/,r)}1' \
  > "$tg_proxy_files/config.toml"


echo "${nl}${bold}All secrets have been set up. Current file structure:${reset}"
tree -a $services_files


#######################  STARTING SERVICES  #######################

echo "${nl}${bold}Starting up services:${reset}"

docker compose --file "$DIR/compose.yml" up --detach
