#!/bin/sh

set -eu

for file in /usr/local/bin/test/*; do
  if [ -f "$file" ] && [ -x "$file" ]; then
    filename=$(basename "$file")
    ln -sf ./test/"$filename" /usr/local/bin/"${filename%.*}"
  fi
done

nft add table ip tun2socks
nft add chain ip tun2socks output { type route hook output priority mangle\; policy accept\; }

function setup_tun() {
  port=$1
  dev=tun_${port}
  ip1=$(( port / 10000 ))
  ip2=$(( (port - ip1 * 10000) / 100 ))
  ip3=$(( port - ip1 * 10000 - ip2 * 100 ))
  cidr=10.${ip1}.${ip2}.${ip3}/32

  ip tuntap add mode tun dev ${dev}
  ip addr add ${cidr} dev ${dev}
  ip link set dev ${dev} up
  
  ip route add default dev ${dev} table ${port}
  ip rule add fwmark 0x${port} table ${port} priority ${port}

  nft add rule ip tun2socks output ip saddr ${cidr} meta mark set 0x${port}
}

# in.socks.test.out.vision.reality
setup_tun 9000
setup_tun 9004
setup_tun 9006

# in.socks.test.out.xhttp.packet-up
setup_tun 9100
setup_tun 9104
setup_tun 9106

# in.socks.test.out.xhttp.stream-up
setup_tun 9200
setup_tun 9204
setup_tun 9206

# in.socks.test.out.xhttp.cdn
setup_tun 9300
setup_tun 9304
setup_tun 9306

/usr/bin/supervisord -c /etc/supervisord.conf
