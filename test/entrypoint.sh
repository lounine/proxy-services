#!/bin/sh

set -eu

function setup_tun() {
  port=$1
  ip1=$(( port / 10000 ))
  ip2=$(( (port - ip1 * 10000) / 100 ))
  ip3=$(( port - ip1 * 10000 - ip2 * 100 ))
  ip=10.${ip1}.${ip2}.${ip3}

  ip tuntap add mode tun dev tun_${port}
  ip addr add ${ip}/32 dev tun_${port}
  ip link set dev tun_${port} up
}

setup_tun 1080
setup_tun 1081
setup_tun 1082
setup_tun 1083

/usr/bin/supervisord -c /etc/supervisord.conf
