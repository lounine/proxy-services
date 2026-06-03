#!/usr/bin/env bash

set -eu

BRANCH_NAME='self-steal'

install -m 0755 -d $HOME/.proxy_services
cd $HOME/.proxy_services


##########################  DOWNLOADING CONFIGS  ###########################

echo "Downloading latest configs..."

TEMP_DIR=$(mktemp -d)
[ -d "$TEMP_DIR" ] || { echo "Could not create temp dir"; exit 1; }
cleanup() { rm -rf "$TEMP_DIR"; };    trap cleanup EXIT

curl -o "$TEMP_DIR/sources.zip" \
     -fsSL https://github.com/lounine/proxy-services/archive/refs/heads/$BRANCH_NAME.zip
unzip -q "$TEMP_DIR/sources.zip" -d "$TEMP_DIR"
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/compose.yml" .
rm -rf ./setup;     mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/setup" .
rm -rf ./test;      mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/test" .
rm -rf ./template;  install -m 0755 -d ./template
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/nginx" ./template/nginx
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/mtg" ./template/mtg
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/xray" ./template/xray


############################  SETTING UP SYSTEM  ###########################

if [ ! -f .installed-system-packages ]; then
  sudo ./setup/system.sh
  touch .installed-system-packages
fi

if [ ! -f .installed-docker ]; then
  sudo ./setup/docker.sh
  touch .installed-docker
fi


##########################  SETTING UP SERVICES  ###########################

install -m 0750 -d ./certs
install -m 0750 -d ./acme.sh

./setup/config.sh "$@"

sudo docker compose up --detach

if [ ! -f .installed-certificates ]; then
  sudo ./setup/certs.sh
  touch .installed-certificates
fi
