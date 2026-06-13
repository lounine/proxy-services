#!/usr/bin/env bash

set -eu

BRANCH_NAME='self-steal'

install -m 755 -d $HOME/.proxy_services
cd $HOME/.proxy_services


#######################  INSTALLING SYSTEM PACKAGES  #######################

ARCH=$(dpkg --print-architecture)

if [ ! -f .installed-system-packages ]; then
  echo "Installing system packages..."

  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
    curl unzip ca-certificates gnupg apache2-utils tree

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
rm -rf ./setup;     mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/setup" .
rm -rf ./test;      mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/test" .
rm -rf ./template;  install -m 755 -d ./template
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/nginx" ./template/nginx
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/mtg" ./template/mtg
mv "$TEMP_DIR/proxy-services-$BRANCH_NAME/xray" ./template/xray


###########################  INSTALLING DOCKER  ############################

if [ ! -f .installed-docker ]; then
  sudo ./setup/docker.sh
  touch .installed-docker
fi


##########################  SETTING UP SERVICES  ###########################

install -m 750 -d ./acme
install -m 550 -d ./certs
sudo chown 101:65532 ./certs     # ensure nginx and xray can both list certs

./setup/config.sh "$@"

sudo docker compose up --detach

if [ ! -f .installed-certificates ]; then
  sudo ./setup/certs.sh
  touch .installed-certificates
fi
