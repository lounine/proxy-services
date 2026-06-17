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
{{ if test.IsKind "slice" .local.xray.xhttp.domains.cdn -}}
  {{ join .local.xray.xhttp.domains.cdn "\n" }}
{{- end -}}
EOF
)

email="admin@${domains[0]}"
echo "${green}Registering account for <$email>:${reset}"
docker exec acme --register-account --server letsencrypt -m "$email"

issued=$(sudo docker exec acme --list)

for domain in "${domains[@]}"; do
  if echo "$issued" | grep -q "^$domain"; then
    echo "${cyan}Certificate for $domain already issued${reset}"
  else
    echo "${green}Issuing certificate for $domain:${reset}"
    docker exec acme --issue --server letsencrypt --standalone --domain $domain
    docker exec acme --deploy --deploy-hook haproxy --domain $domain
  fi
done

echo "${green}Issued certificates:${reset}"
sudo docker exec acme --list

echo "${nl}${green}Deployed certificates:${reset}"
echo "show ssl cert" | sudo docker compose exec --no-tty acme \
                       socat /var/lib/haproxy/admin.sock -
