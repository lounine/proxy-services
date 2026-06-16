#!/usr/bin/env bash

set -eu

BRANCH_NAME='self-steal'

[ -d $HOME/.proxy_services ] || install -m 755 -d $HOME/.proxy_services
cd $HOME/.proxy_services


##############################  SYSTEM SETUP  ##############################

if [ ! -f .installed-system ]; then
  echo "net.ipv4.tcp_fastopen = 3" | sudo tee /etc/sysctl.d/10-tfo.conf
  sudo sysctl -p /etc/sysctl.d/10-tfo.conf

  touch .installed-system
fi


#######################  INSTALLING SYSTEM PACKAGES  #######################

ARCH=$(dpkg --print-architecture)

if [ ! -f .installed-system-packages ]; then
  echo "Installing system packages..."

  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
    curl unzip ca-certificates gnupg apache2-utils socat tree

  echo "Installing gomplate... "
  sudo curl -o /usr/local/bin/gomplate \
        -fsSL https://github.com/hairyhenderson/gomplate/releases/latest/download/gomplate_linux-${ARCH}
  sudo chmod 755 /usr/local/bin/gomplate

  touch .installed-system-packages
fi


##########################  DOWNLOADING CONFIGS  ###########################

echo "Downloading latest configs..."

TEMP_DIR=$(mktemp -d)
[ -d "$TEMP_DIR" ] || { echo "Could not create temp dir"; exit 1; }
cleanup() { rm -rf "$TEMP_DIR"; };    trap cleanup EXIT

curl -o "$TEMP_DIR/sources.zip" \
     -fsSL https://github.com/lounine/proxy-services/archive/refs/heads/$BRANCH_NAME.zip
unzip -q "$TEMP_DIR/sources.zip" -d "$TEMP_DIR"
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/compose.yml" .
rm -rf ./setup;         mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/setup" .
rm -rf ./template;      mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/template" .
rm -rf ./test;          mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/test" .
rm -rf ./test-server;   mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/test-server" .


###########################  INSTALLING DOCKER  ############################

if [ ! -f .installed-docker ]; then
  sudo ./setup/docker.sh
  touch .installed-docker
fi


##########################  SETTING UP SERVICES  ###########################

./setup/config.sh "$@"

sudo docker compose up --detach

if [ ! -f .installed-certificates ]; then
  sudo ./setup/certs.sh
  touch .installed-certificates
fi
