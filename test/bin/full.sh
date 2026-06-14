#!/usr/bin/env bash

set -eu

if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != 'dumb' ] && [ "$TERM" != 'unknown' ]; then
  black=$(tput setaf 0); red=$(tput setaf 1); green=$(tput setaf 2); 
  yellow=$(tput setaf 3); blue=$(tput setaf 4); magenta=$(tput setaf 5); 
  cyan=$(tput setaf 6); white=$(tput setaf 7)
  bold=$(tput bold); ul=$(tput smul); reset=$(tput sgr 0)
else
  black=''; red=''; green=''; yellow=''; blue=''; magenta=''; cyan=''; white=''
  bold=''; ul=''; reset=''
fi

nl=$'\n'


function get_socks_port() {
  local proto=$1
  local ip=${2:-}

  case "$proto" in
    'vision.reality' )    socks_port=9000   ;;
    'xhttp.xray' )        socks_port=9100   ;;
    'xhttp.haproxy' )     socks_port=9200   ;;
    'xhttp.nginx' )       socks_port=9300   ;;
    'xhttp.caddy' )       socks_port=9400   ;;
    'xhttp.cdn' )         socks_port=9500   ;;
    *)                    echo "Unknown protocol: $proto";  exit 1   ;;
  esac

  case "${ip,,}" in
    ipv4|ip4|v4 )     socks_port=$((socks_port + 4))   ;;
    ipv6|ip6|v6 )     socks_port=$((socks_port + 6))   ;;
  esac

  echo $socks_port
}

function check_internet_access() {
  URL_204='https://connectivitycheck.gstatic.com/generate_204'

  local port=$1
  local ip=${2:-}
  local ip_flag=''
  [[ ${ip,,} =~ ^(ipv4|ip4|v4)$ ]] && ip_flag='--ipv4'
  [[ ${ip,,} =~ ^(ipv6|ip6|v6)$ ]] && ip_flag='--ipv6'

  local result=$(curl $ip_flag --silent --connect-timeout 5 -x "socks5://xray:$port" --head "$URL_204" | head -n 1 | cut -d$' ' -f2)

  [[ "$result" == '204' ]]
}

function check_speed() {
  local port=$1
  local dir=${2:-}
  local R_flag=''
  [[ "${dir,,}" == 'down' ]] && R_flag='-R'
  local json=$(iperf3 --json --bind-dev tun_$port --time 3 --omit 2 --connect-timeout 3000 $R_flag --client test-remote)

  local speed=$(echo "$json" | jq '.end.sum_received.bits_per_second')

  echo "$speed" | numfmt --to=si --suffix=b/s | sed -E 's#([0-9.]*)#\1 #'
}

function column () {
  local format=${1:-}
  local width=${2:-8}
  local input; read input
  if [[ "$input" == '-' ]]; then
    seq -s '-' 1 $(( width + 3 )) | tr -d '0-9\n'; printf '|'
  else
    printf "${format} %${width}s ${reset}|" "$input"
  fi
}

function check_connection_and_speed() {
  local proto=$1
  local ip=$2
  local port=$(get_socks_port $proto $ip)

  if check_internet_access $port; then
    echo 'PASS' | column "${green}" 4
    check_speed $port up   | column
    check_speed $port down | column
  else
    echo 'FAIL' | column "${red}" 4
    echo '--' | column "${red}"
    echo '--' | column "${red}"
  fi
}


function run_tests_for_protocol() {
  local proto=$1
  local title_length=$2
  echo $proto | column "${bold}" $title_length

  check_connection_and_speed $proto 'IPv4'
  check_connection_and_speed $proto 'IPv6'

  echo
}

function run_tests() {
  local protocols=(
    'vision.reality'
    'xhttp.xray'
    'xhttp.haproxy'
    'xhttp.caddy'
    'xhttp.nginx'
    'xhttp.cdn'
  )

  # calculate longest protocol name
  local title_length=0
  for proto in "${protocols[@]}"; do
    if (( ${#proto} > title_length )); then
      title_length=${#proto}
    fi
  done

  echo
  echo '' | column "${bold}" $title_length
  echo 'IP4' | column "${bold}" 4 
  echo 'up' | column "${bold}"
  echo 'down' | column "${bold}"
  echo 'IP6' | column "${bold}" 4
  echo 'up' | column "${bold}"
  echo 'down' | column "${bold}"
  echo

  echo '-' | column '' $title_length
  echo '-' | column "${bold}" 4 
  echo '-' | column "${bold}"
  echo '-' | column "${bold}"
  echo '-' | column "${bold}" 4
  echo '-' | column "${bold}"
  echo '-' | column "${bold}"
  echo

  for proto in "${protocols[@]}"; do
    run_tests_for_protocol "$proto" $title_length
  done
}

function get_address() {
  local port=$1
  local ip=${2:-}
  local prefix='api'
  [[ ${ip,,} =~ ^(ipv4|ip4|v4)$ ]] && prefix='api4'
  [[ ${ip,,} =~ ^(ipv6|ip6|v6)$ ]] && prefix='api6'

  IPIFY_URL="https://${prefix}.ipify.org"

  curl --silent --connect-timeout 5 -x "socks5://xray:${port}" "${IPIFY_URL}"
}

function print_address() {
  local ip=${1:-IPv4}
  local port=$(get_socks_port 'vision.reality')

  local address=$(get_address ${port} ${ip})

  if [[ -n "${address}" ]]; then
    local host=$(dig -x "${address}" @1.1.1.1 +short | sed 's/\.*$//' )
    echo "${bold}${ip}:${reset} ${address} (${host})"
  else
    echo "No ${ip}"
  fi
}

function print_addresses() {
  echo "${bold}Accessing web from addresses:${reset}"
  print_address 'IPv4'
  print_address 'IPv6'
}

run_tests
echo
print_addresses
