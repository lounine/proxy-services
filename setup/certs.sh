#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/_common.sh

cd "$SCRIPT_DIR"/..


####################  CHECKING / PREPARING ENVIRONMENT  ####################

if [ $EUID -ne 0 ]; then
  echo "${bold}This script should be run with root privileges. Please use sudo.${reset}"
  exit 1
fi


##########################  ISSUING CERTIFICATES  ##########################

echo "${nl}${bold}Issuing certificates:${reset}"

readarray -t domains < <( gomplate << 'EOF'
  {{ join .local.xray.reality.domains " " }}
  {{ join .local.xray.xhttp.domains.xray " " }}
  {{ join .local.xray.xhttp.domains.nginx " " }}
  {{ join .local.xray.xhttp.domains.haproxy " " }}
  {{ join .local.xray.xhttp.domains.cdn " " }}
  {{ .params.telegram.domain }}
EOF
)

email="admin@${domains[0]}"
echo "${green}Registering account for <$email>:${reset}"
docker exec acme --register-account --server letsencrypt -m "$email"

for domain in "${domains[@]}"; do
  echo "${green}Issuing certificate for $domain:${reset}"
  docker exec acme --issue --server letsencrypt --standalone -d $domain \
                   --fullchain-file /certs/$domain.crt --key-file /certs/$domain.key \
                   --reloadcmd 'chmod 640 /certs/*' || : # already issued certificates provoke error here
done
