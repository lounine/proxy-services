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

setup_tun 9000
setup_tun 9004
setup_tun 9006
setup_tun 9100
setup_tun 9104
setup_tun 9106
setup_tun 9200
setup_tun 9204
setup_tun 9206
setup_tun 9300
setup_tun 9304
setup_tun 9306

/usr/bin/supervisord -c /etc/supervisord.conf
