#!/bin/sh

set -eu

function setup_tun() {
  id=$1
  ip tuntap add mode tun dev tun${id}
  ip addr add 10.0.10.${id}/15 dev tun${id}
  ip link set dev tun${id} up
}

setup_tun 80
setup_tun 81
setup_tun 82
setup_tun 83

/usr/bin/supervisord
