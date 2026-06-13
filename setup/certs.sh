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

email="$( echo 'admin@{{ index .local.xray.xhttp.domains 0 }}' |  gomplate )"
echo "${green}Registering account for <$email>:${reset}"
docker exec acme --register-account --server letsencrypt -m "$email"

domains=$( gomplate << 'EOF'
  {{ join .local.xray.reality.domains " " }}
  {{ join .local.xray.xhttp.domains " " }}
  {{ .params.telegram.domain }}
EOF
)

# to grant access to nginx (101) and xray (65532)
certs_reload_cmd='chown 101:65532 /certs/*; chmod 440 /certs/*'

for domain in $domains; do
  echo "${green}Issuing certificate for $domain:${reset}"
  docker exec acme --issue --server letsencrypt --standalone -d $domain \
                   --fullchain-file /certs/$domain.crt --key-file /certs/$domain.key \
                   --reloadcmd "$certs_reload_cmd" || : # already issued certificates provoke error here
done
