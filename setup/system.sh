#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/_common.sh


####################  CHECKING / PREPARING ENVIRONMENT  ####################

if [ $EUID -ne 0 ]; then
  echo "${bold}This script should be run with root privileges. Please use sudo.${reset}"
  exit 1
fi

ARCH=$(dpkg --print-architecture)


#######################  INSTALLING SYSTEM PACKAGES  #######################

echo "${nl}${bold}Installing system packages${reset}"

apt-get update
apt-get install -y --no-install-recommends \
  curl unzip ca-certificates gnupg apache2-utils tree

echo "Installing gomplate... "
curl -o /usr/local/bin/gomplate \
      -fsSL https://github.com/hairyhenderson/gomplate/releases/latest/download/gomplate_linux-${ARCH}
chmod 0755 /usr/local/bin/gomplate
