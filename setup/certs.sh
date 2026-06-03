#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$SCRIPT_DIR"/_common.sh

cd "$SCRIPT_DIR"/..


##########################  ISSUING CERTIFICATES  ##########################

echo "${nl}${bold}Issuing certificates:${reset}"

email="$( echo 'admin@{{ index .local.xray.xhttp.domains 0 }}' |  gomplate )"
echo "${green}Registering account for <$email>:${reset}"
docker exec acme.sh --register-account --server letsencrypt -m "$email"

domains=$( gomplate << 'EOF'
  {{ join .local.xray.reality.domains " " }}
  {{ join .local.xray.xhttp.domains " " }}
  {{ .params.telegram.domain }}
EOF
)

for domain in $domains; do
  echo "${green}Issuing certificate for $domain:${reset}"
  docker exec acme.sh --issue --server letsencrypt --standalone -d $domain \
                      --fullchain-file /certs/$domain.crt --key-file /certs/$domain.key \
                      --reloadcmd 'chown 101:101 /certs/*' || : # already issued certificates provoke error here
                                  #nginx user and group
done
