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

readarray -t domains < <( gomplate << 'EOF' | sed 's/[[:space:]]*//g'
  {{ join .local.xray.reality.domains "\n" }}
  {{ join .local.xray.xhttp.domains.direct "\n" }}
  {{ join .local.xray.xhttp.domains.cdn "\n" }}
EOF
)

email="admin@${domains[0]}"
echo "${green}Registering account for <$email>:${reset}"
docker exec acme --register-account --server letsencrypt -m "$email"

for domain in "${domains[@]}"; do
  echo "${green}Issuing certificate for $domain:${reset}"
  docker exec acme --issue --server letsencrypt --standalone --domain $domain
  docker exec acme --deploy --deploy-hook haproxy --domain $domain
                   
done
